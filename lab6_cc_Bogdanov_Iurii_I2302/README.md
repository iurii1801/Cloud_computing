# Лабораторная работа №6. Балансирование нагрузки в облаке и авто-масштабирование

## Цель работы

Закрепить навыки работы с AWS EC2, Elastic Load Balancer, Auto Scaling и CloudWatch, создав отказоустойчивую и автоматически масштабируемую архитектуру.

Будут развёрнуты:

- VPC с публичными и приватными подсетями;
- Виртуальная машина с веб-сервером (nginx);
- Application Load Balancer;
- Auto Scaling Group (на основе AMI);
- нагрузочный тест с использованием CloudWatch.

## Ход выполнения работы

### Дополнительное условие для специализации DevOps

Для получения высшей оценки необходимо не создавать VPC и виртуальную машину вручную через веб-интерфейс AWS, а автоматизировать развёртывание с помощью Terraform.  
В рамках работы Terraform-конфигурация должна:

- создать VPC с двумя публичными и двумя приватными подсетями;
- создать Internet Gateway и таблицу маршрутизации для публичных подсетей;
- создать Security Group с доступом по SSH (22) и HTTP (80);
- запустить экземпляр EC2 с ОС Amazon Linux 2 и выполнить скрипт `init.sh` через `user_data` для установки веб-сервера.

### Подготовка инфраструктуры с Terraform

#### Файл `main.tf`

Для начала необходимо создать файл **`main.tf`**, который будет содержать описание всей инфраструктуры.

```tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.5.0"
}

provider "aws" {
  region = var.aws_region
}

# Доступные зоны (чтобы разбросать подсети по разным AZ)
data "aws_availability_zones" "available" {
  state = "available"
}

# Ищем последнюю Amazon Linux 2 AMI (x86_64, gp2)
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ========== VPC ==========
resource "aws_vpc" "lab6_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "lab6-vpc"
    Lab  = "cloud-computing-6"
  }
}

# ========== Internet Gateway ==========
resource "aws_internet_gateway" "lab6_igw" {
  vpc_id = aws_vpc.lab6_vpc.id

  tags = {
    Name = "lab6-igw"
  }
}

# ========== Публичные подсети ==========
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.lab6_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "lab6-public-1"
    Type = "public"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.lab6_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "lab6-public-2"
    Type = "public"
  }
}

# ========== Приватные подсети (для Auto Scaling позже) ==========
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.lab6_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "lab6-private-1"
    Type = "private"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.lab6_vpc.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "lab6-private-2"
    Type = "private"
  }
}

# ========== Route table для публичных подсетей ==========
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab6_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab6_igw.id
  }

  tags = {
    Name = "lab6-public-rt"
  }
}

resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# ========== Security Group для веб-сервера ==========
resource "aws_security_group" "web_sg" {
  name        = "lab6-web-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.lab6_vpc.id

  # SSH 
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP для всех
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lab6-web-sg"
  }
}

# ========== EC2: Amazon Linux 2 + init.sh ==========
resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  associate_public_ip_address = true
  monitoring                  = true # Detailed CloudWatch monitoring (Enable)

  key_name = "lab6-key"

  # UserData — скрипт init.sh
  user_data = file("${path.module}/init.sh")
  user_data_replace_on_change = true
  tags = {
    Name = "lab6-web-ec2"
    Role = "web"
  }
}
```

В файле `main.tf` описывается основная инфраструктура в AWS:

- провайдер `aws` с указанием региона;
- VPC с заданным CIDR-блоком;
- две публичные и две приватные подсети в разных зонах доступности;
- Internet Gateway и таблица маршрутизации, в которой для публичных подсетей прописывается маршрут `0.0.0.0/0` через Internet Gateway;
- группа безопасности, в которой открывается:
  - порт 22 (SSH) в учебной конфигурации открыт для всех (`0.0.0.0/0`) для удобства подключения; в реальной среде рекомендуется ограничивать доступ только своим публичным IP-адресом;
  - порт 80 (HTTP) открыт для всех (`0.0.0.0/0`), чтобы веб-сервис был доступен из интернета.
- ресурс `aws_instance "web_server"`, который:
  - использует AMI `Amazon Linux 2`;
  - тип экземпляра `t3.micro`;
  - подключается к одной из публичных подсетей;
  - получает публичный IP-адрес;
  - использует созданную группу безопасности;
  - привязывается к ключу `lab6-key` (файл `lab6-key.pem` указывается при SSH-подключении);
  - получает скрипт `init.sh` через параметр `user_data`, чтобы автоматически установить и настроить веб-сервер при первом запуске;
  - получает теги `Name = "lab6-web-ec2"` и `Role = "web"` для удобной идентификации.

Таким образом, `main.tf` описывает все ресурсы, которые должны быть созданы в AWS для выполнения шагов 1 и 2 лабораторной работы.

#### Файл `variables.tf`

Далее необходимо создать файл **`variables.tf`**.

```tf
variable "aws_region" {
  description = "AWS region for lab 6"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for web server"
  type        = string
  default     = "t3.micro"
}
```

В файле `variables.tf` описываются входные параметры конфигурации.

Задаются:

- **регион AWS** (`aws_region`);
- **тип EC2-инстанса** (`instance_type`), используемый для веб-сервера.

Остальные параметры (CIDR-блок VPC, подсети, имя ключа и теги) зашиваются прямо в `main.tf` для упрощения конфигурации.

#### Создание файла `terraform.tfvars`

После определения всех переменных в файле `variables.tf` необходимо создать файл **`terraform.tfvars`**, в котором задаются конкретные значения для переменных конфигурации.

Этот файл позволяет отделить логику инфраструктуры от параметров, чтобы удобно менять настройки, не изменяя основной код.

Файл должен находиться в корне Terraform-проекта, рядом с `main.tf`.

```tfvars
aws_region    = "us-east-1"
instance_type = "t3.micro"
```

В файле указываются такие параметры как:

- **aws_region** — определяет регион, в котором будет создана VPC, подсети и EC2-инстанс.
- **instance_type** — задаёт тип EC2-инстанса, который используется для развёртывания веб-сервера.

В дальнейшем Terraform автоматически подставляет эти значения в файл `main.tf` при выполнении команд `terraform plan` и `terraform apply`.

#### Файл `outputs.tf`

После этого необходимо создать файл **`outputs.tf`**, который определяет, какие значения Terraform должен вывести после развёртывания.

```tf
output "vpc_id" {
  description = "ID созданной VPC"
  value       = aws_vpc.lab6_vpc.id
}

output "public_subnet_ids" {
  description = "IDs публичных подсетей"
  value = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id,
  ]
}

output "private_subnet_ids" {
  description = "IDs приватных подсетей"
  value = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id,
  ]
}

output "web_instance_public_ip" {
  description = "Public IP веб-сервера"
  value       = aws_instance.web_server.public_ip
}

output "web_instance_public_dns" {
  description = "Public DNS веб-сервера"
  value       = aws_instance.web_server.public_dns
}
```

В частности, выводятся:

- `vpc_id` — идентификатор созданной VPC;
- списки идентификаторов приватных и публичных подсетей;
- `web_instance_public_dns` — публичное DNS-имя веб-инстанса;
- `web_instance_public_ip` — публичный IP-адрес веб-инстанса.

Эти данные далее используются для подключения к серверу по SSH и проверки работы веб-приложения через браузер.

#### Скрипт `init.sh`

Затем необходимо создать файл **`init.sh`**, который будет автоматически выполнен при первом запуске EC2-инстанса через механизм `user_data`.

Скрипт передаётся в EC2-машину из Terraform и выполняет следующее:

- ожидает, пока менеджер пакетов `yum` освободится от фоновой работы;
- обновляет пакеты системы;
- устанавливает nginx через **Amazon Linux Extras**;
- устанавливает PHP, PHP-FPM и PHP-CLI через `yum`;
- создаёт директорию сайта `/var/www/html`;
- формирует `index.php` с выводом имени хоста и функцией генерации нагрузки CPU;
- создаёт конфигурацию nginx `/etc/nginx/conf.d/lab6.conf`, перенаправляя обработку `.php` в PHP-FPM;
- удаляет дефолтные конфиги nginx;
- меняет владельца каталога сайта на пользователя `nginx`;
- проверяет конфигурацию nginx и запускает веб-сервер.

Скрипт:

```sh
#!/bin/bash
set -xe

# Ждём, пока yum не будет занят другим процессом
while sudo fuser /var/run/yum.pid >/dev/null 2>&1; do
  echo "YUM занят, ждём 5 секунд..."
  sleep 5
done

# Обновление системы
yum update -y

# Установка Nginx через Amazon Linux Extras + PHP-FPM
amazon-linux-extras install -y nginx1
yum install -y php php-fpm php-cli

# Включаем автозапуск сервисов
systemctl enable nginx
systemctl enable php-fpm

# Создаём директорию под сайт
mkdir -p /var/www/html

cat > /var/www/html/index.php <<'EOF'
<?php
$hostname = gethostname();

if (strpos($_SERVER['REQUEST_URI'], '/load') === 0) {
    runCpuLoad();
    exit;
}

function runCpuLoad(): void
{
    ini_set('max_execution_time', '600');

    $seconds = isset($_GET['seconds']) ? (int)$_GET['seconds'] : 60;
    $seconds = max(30, min($seconds, 600)); // от 30 до 600 сек

    $endTime = microtime(true) + $seconds;
    $dummy   = 0.0;

    while (microtime(true) < $endTime) {
        $dummy += sqrt(mt_rand(1, 1000));
    }

    echo "<h2>Load finished</h2>";
    echo "<p>Seconds: {$seconds}</p>";
    echo "<p>Dummy value: {$dummy}</p>";
}

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Lab 6 Web Server</title>
</head>
<body>
<h1>Hello from <?php echo htmlspecialchars($hostname, ENT_QUOTES); ?></h1>
<p><a href="/load?seconds=60">Generate CPU load for 60 seconds</a></p>
</body>
</html>
EOF

# Конфиг Nginx для PHP
cat > /etc/nginx/conf.d/lab6.conf <<'EOF'
server {
    listen 80;
    server_name _;

    root /var/www/html;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include /etc/nginx/fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
EOF

# Чистим дефолтные конфиги (если есть)
rm -f /etc/nginx/conf.d/*.default

# Меняем права на каталог сайта
chown -R nginx:nginx /var/www/html

# Проверяем конфиг и запускаем сервисы
nginx -t
systemctl restart php-fpm
systemctl restart nginx
```

### Практическая часть

#### 1. Запуск Terraform и развёртывание инфраструктуры

На данном этапе необходимо перейти в каталог с Terraform-конфигурацией:

```bash
cd terraform
```

Перед первым запуском требуется инициализировать рабочий каталог Terraform:

```bash
terraform init
```

![image](https://i.imgur.com/k0613rP.png)

Команда скачивает необходимые провайдеры и подготавливает каталог к дальнейшей работе.

Затем выполняется развёртывание инфраструктуры:

```bash
terraform apply
```

Команда `terraform apply` использует все файлы конфигурации (`*.tf` и `terraform.tfvars`) в каталоге, создаёт в AWS VPC, подсети, Internet Gateway, группу безопасности и экземпляр EC2. После успешного выполнения выводятся значения, определённые в `outputs.tf`:

- идентификатор VPC;
- идентификаторы приватных и публичных подсетей;
- публичный DNS-адрес и публичный IP-адрес веб-сервера.

![image](https://i.imgur.com/a4Otw7j.png)  

Полученный публичный IP-адрес используется далее для подключения по SSH и для проверки сайта в браузере.

#### 2. Подключение по SSH к веб-серверу Amazon EC2

После завершения работы Terraform необходимо подключиться к созданному экземпляру EC2 по SSH, используя ключ `lab6-key.pem`:

```bash
ssh -i "E:\anul3\Cloud_computing\lab6_cc_Bogdanov_Iurii_I2302\terraform\lab6-key.pem" ec2-user@<web_instance_public_ip>
```

В результате устанавливается SSH-сессия с сервером под пользователем `ec2-user`. В приветственном сообщении отображается, что на инстансе установлена ОС Amazon Linux 2.

Далее выполняется проверка статуса веб-сервера nginx:

```bash
sudo systemctl status nginx
```

Команда показывает, что служба nginx загружена и находится в состоянии `active (running)`. Это означает, что скрипт `init.sh`, переданный через `user_data`, успешно отработал и запустил веб-сервер.

![image](https://i.imgur.com/cUedIrp.png)

#### 3. Проверка работы веб-приложения через браузер

После проверки сервисов на стороне сервера необходимо убедиться, что веб-приложение доступно по HTTP.

Для этого в адресной строке браузера вводится публичный IP-адрес инстанса:

```text
http://<web_instance_public_ip>
```

В результате открывается страница `index.php`, созданная скриптом `init.sh`. На странице отображается:

![image](https://i.imgur.com/oJJDRL8.png)

- заголовок вида `Hello from ip-10-0-1-29.ec2.internal`, где используется имя хоста, полученное функцией `gethostname()`;
- ссылка `Generate CPU load for 60 seconds`, которая обращается к пути `/load?seconds=60` и запускает PHP-функцию `runCpuLoad()` для генерации загрузки CPU.

Таким образом подтверждается, что:

- nginx корректно обслуживает HTTP-запросы на порт 80;
- PHP и `php-fpm` успешно обрабатывают файл `index.php`;
- сервер готов к дальнейшим шагам лабораторной работы (создание AMI, Launch Template, Load Balancer и Auto Scaling Group).

> Шаги 1 и 2 лабораторной работы («Создание VPC и подсетей» и «Создание и настройка виртуальной машины») были выполнены автоматически с помощью Terraform, что соответствует дополнительному требованию для студентов специализации DevOps.
>
> В результате Terraform-конфигурации были созданы:
> — VPC с публичными и приватными подсетями;
> — Internet Gateway и таблица маршрутизации;
> — Security Group;
> — EC2-инстанс с Amazon Linux 2;
> — автоматическая установка nginx и PHP через script `init.sh` (user_data).
>
> После проверки доступности веб-приложения можно переходить к выполнению **шага 3 лабораторной работы — созданию AMI**.

### Шаг 3. Создание `AMI`

На данном этапе необходимо создать собственный образ виртуальной машины (**AMI**) на основе EC2-инстанса, который был развёрнут в шагах 1–2 при помощи Terraform. Созданная AMI далее будет использоваться в Launch Template и Auto Scaling Group.

#### 3.1. Переход к созданию `AMI`

Необходимо открыть список EC2-инстансов
`EC2 → Instances`.

Затем выбрать созданный сервер `lab6-web-ec2`, нажать **Actions → Image and templates → Create image**.

![image](https://i.imgur.com/IPyl0Dr.png)

#### 3.2. Заполнение параметров создаваемой AMI

Откроется окно создания образа.

Следует заполнить параметры:

- **Image name:** `project-web-server-ami`
- **Reboot instance:** оставить включённым (по умолчанию).
  Это обеспечивает корректность создаваемого образа.

![image](https://i.imgur.com/CiDyw20.png)

#### 3.3. Проверка создания AMI

В правом верхнем углу появится уведомление:

![image](https://i.imgur.com/1pRd6VJ.png)

После этого необходимо открыть раздел:

`EC2 → AMIs`

В списке AMI должна появиться созданная запись со статусом `Pending` → `Available`.

![image](https://i.imgur.com/cM6u2iV.png)

Когда статус изменится на **Available**, AMI готова к использованию.

>**Вопрос:**
>
> Что такое `image` и чем он отличается от `snapshot`? Какие есть варианты использования AMI?
>
>**Ответ:**
>
>**`AMI (image)`** — это готовый шаблон виртуальной машины.
Он включает **операционную систему, программы, настройки и конфигурацию сервера**.
Из AMI можно сразу запускать новые EC2-инстансы.
>
>**`Snapshot`** — это просто **резервная копия диска** (EBS-тома).
Он хранит только данные, без информации об ОС, настройках и конфигурации машины.
>
>**Разница:**
>
>- **`AMI` — это полный образ сервера. Можно сразу запускать EC2.**
>- **`Snapshot` — это копия диска. EC2 из него запустить нельзя.**
>
>**Для чего используют `AMI`:**
>
>- запуск новых одинаковых серверов;
>- создание Launch Template;
>- Auto Scaling Group;
>- быстрое восстановление рабочей конфигурации сервера.

### Шаг 4. Создание `Launch Template`

На основе **`Launch Template`** в дальнейшем будет создаваться Auto Scaling Group, то есть новые инстансы будут подниматься по одному и тому же шаблону (с уже установленным nginx и PHP из нашей AMI).

1. В консоли **EC2** необходимо перейти в раздел **Launch templates** и нажать кнопку **Create launch template**.

2. В блоке **Launch template name and description** необходимо заполнить поля:

   - **Launch template name** – `project-launch-template`;
   - при желании можно указать краткое описание версии (оставлено по умолчанию).

3. В разделе **Application and OS Images (Amazon Machine Image)** нужно выбрать вкладку **My AMIs** и указать созданную ранее AMI
   **`project-web-server-ami`**.

4. В блоке **Instance type** оставить тип инстанса **`t3.micro`**.

5. В разделе **Network settings**:

   - в пункте **Firewall (security groups)** выбрать **Select existing security group**;
   - указать ту же группу безопасности, что использовалась для веб-инстанса (`lab6-web-sg`).
     Эта группа уже открывает порты **22 (SSH)** и **80 (HTTP)**.

6. В дополнительных настройках (**Advanced details**) нужно включить опцию
   **Detailed CloudWatch monitoring → Enable**, чтобы Auto Scaling имел более детальные метрики по CPU и другим параметрам.

   Необходимо также найти секцию `User data` и добавить скрипт, который автоматически установит веб-сервер и создаст главную страницу при первом запуске EC2-инстанса:

   ```bash
    #!/bin/bash
    sudo yum install -y httpd
    sudo systemctl enable httpd
    sudo systemctl start httpd
    echo "<h1>Welcome</h1>" > /var/www/html/index.html
   ```

7. В конце необходимо нажать **Create launch template**.

В результате создаётся шаблон `project-launch-template` с первой версией (**Version 1 (Default)**), который затем будет использоваться при создании Auto Scaling Group.

![image](https://i.imgur.com/an4C0D5.png)

![image](https://i.imgur.com/k7nBRBz.png)

![image](https://i.imgur.com/AbDgpFe.png)

![image](https://i.imgur.com/Bb2ZZLv.png)

![image](https://i.imgur.com/hLQSESE.png)

![image](https://i.imgur.com/IhFHFAz.png)

![image](https://i.imgur.com/osQR2zZ.png)

![image](https://i.imgur.com/PtzVT0J.png)

>**Вопрос:**
>
> Что такое `Launch Template` и зачем он нужен? Чем он отличается от `Launch Configuration`?
>
>**Ответ:**
>
>- **`Launch Template`** — это шаблон конфигурации EC2-инстанса (AMI, тип, диски, сеть, security group, user data и т.д.), который можно многократно переиспользовать при ручном запуске инстансов, в Auto Scaling Group, Spot Fleet и т.п. У шаблона есть **версии**, поэтому настройки можно обновлять, не создавая шаблон с нуля.
>
>- **`Launch Configuration`** — старый механизм только для Auto Scaling Group: без версий, после создания его нельзя изменить (нужно создавать новый). Сейчас он считается устаревающим, а **`Launch Template`** — более гибкая и современная замена.

### Шаг 5. Создание `Target Group`

После создания `Launch Template` следующим шагом является создание **Target Group**, к которой позже будет привязан `Application Load Balancer` и `Auto Scaling Group`.

`Target Group` определяет, **куда** Load Balancer будет направлять HTTP-трафик, и какие инстансы считаются «здоровыми» (healthy) для обслуживания запросов.

#### 5.1. Переход к созданию Target Group

В консоли AWS необходимо перейти по пути:

**`EC2 → Target Groups → Create target group`**

#### 5.2. Настройка параметров Target Group

В открывшемся окне выбираются параметры:

1. **Target type:** `Instances`
2. **Target group name:** `project-target-group`
3. **Protocol:** `HTTP`
4. **Port:** `80`
5. **VPC:** *выбрать свою VPC, созданную Terraform*

#### 5.3. Настройка health checks

Health checks — это механизм, который Load Balancer использует для проверки, «жив» ли сервер.

Параметры оставляем по умолчанию:

- **Health check protocol:** `HTTP`
- **Path:** `/`
- Timeout: 5 seconds
- Interval: 30 seconds
- Healthy threshold: 5
- Unhealthy threshold: 2
- Success codes: `200`

![image](https://i.imgur.com/a2SDbQH.png)

![image](https://i.imgur.com/MFdpoJH.png)

#### 5.4. Пропуск регистрации Targets

На этом шаге список инстансов будет пустой — это нормально.
Поскольку Auto Scaling Group будет **сама** регистрировать новые EC2-инстансы автоматически.

Здесь просто необходимо нажимать:

**`Next → Create target group`**

![image](https://i.imgur.com/vUxDmaD.png)

![image](https://i.imgur.com/o1YOXB6.png)

#### 5.5. Создание Target Group

После подтверждения появляется окно:

```bash
Successfully created the target group: project-target-group
```

Группа создана, без привязанных инстансов — это правильно на данном этапе.

![image](https://i.imgur.com/akjsTzT.png)

>**Вопрос:**
>
> Зачем необходим и какую роль выполняет `Target Group`?
>
>**Ответ:**
>
>`Target Group` — это список серверов (EC2-инстансов), куда Load Balancer будет отправлять трафик.
Она выполняет две ключевые функции:
>
>1. **Получатель трафика** — сюда Load Balancer направляет HTTP-запросы.
>2. **Health checks** — следит, какие инстансы работают, а какие нет.
>
>Если инстанс становится «unhealthy», Load Balancer перестаёт на него отправлять трафик.
>
>Target Group также используется Auto Scaling Group — новые инстансы автоматически в неё добавляются.

### Шаг 6. Создание Application Load Balancer

После создания Target Group следующим этапом является настройка **Application Load Balancer (ALB)**, который будет распределять входящий HTTP-трафик между EC2-инстансами Auto Scaling Group.

#### 6.1. Переход к созданию Load Balancer

В консоли AWS необходимо перейти по пути:

**`EC2 → Load Balancers → Create Load Balancer → Application Load Balancer`**

#### 6.2. Basic configuration (Основная конфигурация)

Необходимо заполнить поля следующим образом:

1. **Load balancer name:**
   `project-alb`

2. **Scheme:**
   `Internet-facing`

   > ALB будет доступен из интернета и иметь публичный DNS-адрес.

![image](https://i.imgur.com/6hdGzOL.png)

>**Вопрос:**
>
>В чем разница между Internet-facing и Internal?
>
>**Ответ:**
>
>- `Internet-facing` — Load Balancer получает публичный IP-адрес и доступен из интернета.
>- `Internal` — доступен только внутри VPC, не имеет публичного доступа.

3. **IP address type:**
   `IPv4`

#### 6.3. Network mapping (Сетевое размещение)

1. **VPC:**
   выбрать свою VPC, созданную Terraform

2. **Subnets:**
   выбрать **две публичные подсети**:

   - lab6-public-1
   - lab6-public-2

   Load Balancer всегда требует минимум **2 AZ** для высокой доступности.

#### 6.4. Security Groups

Выбрать группу безопасности, которая разрешает входящий HTTP трафик (порт 80).

Используется та же SG, что и для инстансов:

- `lab6-web-sg`

#### 6.5. Настройка `Listener` и default action

- **Listener:**
  Protocol: `HTTP`
  Port: `80`

- **Default action:**
  → `Forward to target groups`
  → выбрать `project-target-group`

![image](https://i.imgur.com/HtLp3JP.png)

![image](https://i.imgur.com/RMGmafy.png)

>**Вопрос:**
>
>Что такое Default action и какие есть типы Default action?
>
>**Ответ:**
>
>**Default action** — это действие, которое Load Balancer выполняет, если не подходит ни одно правило.
>
>Типы действий:
>
>1. **Forward to target groups** — отправить запрос на серверы.
>2. **Redirect to URL** — перенаправить на другой сайт.
>3. **Return fixed response** — вернуть готовый HTTP-ответ (например, текст или код 403).

#### 6.6. Завершение создания `ALB`

Необходимо нажать:

**`Create load balancer`**

После создания появится статус:

`Successfully created load balancer: project-alb`

![image](https://i.imgur.com/ljM9j3y.png)

#### 6.7. Проверка связей в `Resource map`

Необходимо открыть:

**`Load Balancer → Resource map`**

Убедиться, что существуют связи:

- `Listener → Rule → Target Group`

![image](https://i.imgur.com/DekCIE3.png)

### Шаг 7. Создание `Auto Scaling Group`

После создания `Load Balancer` и `Target Group` необходимо настроить **`Auto Scaling Group (ASG)`**, которая автоматически будет запускать новые EC2-инстансы по шаблону `Launch Template` и распределять их по `Availability Zones`.

#### 7.1. Переход к созданию ASG

В AWS-консоли необходимо перейти по пути:

**`EC2 → Auto Scaling Groups → Create Auto Scaling group`**.

На первом экране нужно заполнить блок **Name and launch template**.

1. **Auto Scaling group name:**
   `project-auto-scaling-group`

2. **Launch template:**
   выбрать созданный ранее
   `project-launch-template`

3. В поле **Version** выбрать актуальную версию шаблона (например, Version 3).

![image](https://i.imgur.com/DrrznsG.png)

#### 7.2. Выбор сети и подсетей (Choose instance launch options)

На следующем шаге необходимо:

1. **VPC:**

выбрать свою рабочую VPC (`lab6-vpc`).

2. **Subnets:**

указать **две приватные подсети**:

- `lab6-private-1`
- `lab6-private-2`

>**Вопрос:**
>
>Почему для `Auto Scaling Group` выбираются приватные подсети?
>
>**Ответ:**
>
>Приватные подсети используются для ASG, потому что инстансы в них не имеют публичного доступа.
>К ним можно попасть только через Load Balancer, что повышает безопасность и предотвращает обход балансировщика.
>Такой подход — стандартная схема AWS для защиты приложений.

#### 7.3. Настройка распределения по Availability Zones

В поле **Availability Zone distribution** нужно выбрать:

- **Balanced best effort**

![image](https://i.imgur.com/QCfFd9M.png)

>**Вопрос:**
>
>Зачем нужна настройка `Availability Zone distribution`?
>
>**Ответ:**
>
>Эта настройка распределяет инстансы ASG по разным зонам доступности.
>Это нужно, чтобы приложение продолжало работать, даже если одна зона выйдет из строя, и чтобы нагрузка между зонами распределялась равномерно.

#### 7.4. Интеграция с `Load Balancer`

В разделе **Integrate with other services** выбрать:

- **Attach to an existing load balancer**
- Тип: **Choose from your load balancer target groups**
- Выбрать целевую группу:

`project-target-group`

![image](https://i.imgur.com/ZPGplWj.png)

Таким образом ASG будет автоматически добавлять новые EC2-инстансы в Target Group и подключать их к ALB.

#### 7.5. Настройка размера группы и Scaling Policy

В разделе **Configure group size and scaling** нужно указать:

- **Desired capacity:** `2`
- **Minimum capacity:** `2`
- **Maximum capacity:** `4`

![image](https://i.imgur.com/ES3mimG.png)

Затем включить автоматическое масштабирование:

- **Target tracking scaling policy**

- Metric type: **Average CPU Utilization**
- Target value: **50%**
- Instance warm-up: **60 seconds**

![image](https://i.imgur.com/rBEOuRA.png)

>**Вопрос:**
>
>Что такое `Instance warm-up` и зачем он нужен?
>
>**Ответ:**
>
>`Instance warm-up` — это время, которое даётся новому инстансу, чтобы полностью запуститься.
>Пока он «разогревается», его метрики не учитываются, чтобы `Auto Scaling` не делал ложных решений при увеличении/уменьшении количества инстансов.

#### 7.6. Включение `CloudWatch Metrics`

В разделе **`Additional settings`** необходимо включить галочку:

- **Enable group metrics collection within CloudWatch**

![image](https://i.imgur.com/w6kh2Zs.png)

Это позволит видеть загрузку `ASG`, тенденции масштабирования и состояние инстансов.

#### 7.7. Завершение создания `ASG`

После проверки всех параметров на шаге **Review** нажать:

- **Create `Auto Scaling group`**

После создания ASG появится в списке со значениями:

- **Desired capacity: 2**
- **Min: 2**
- **Max: 4**
- **Launch template: project-launch-template**

![image](https://i.imgur.com/xXvCGgZ.png)

### Шаг 8. Тестирование `Application Load Balancer`

После создания `Load Balancer` и привязки `Auto Scaling Group` необходимо убедиться, что балансировщик действительно распределяет трафик между несколькими EC2-инстансами.

#### 8.1. Получение DNS Load Balancer

- Необходимо перейти в **`EC2 → Load Balancers`**
- Выбрать балансировщик **project-alb**
- Скопировать его **DNS-имя**, например:

```bash
project-alb-1356575818.us-east-1.elb.amazonaws.com
```

#### 8.2. Открытие `DNS` в браузере

Необходимо вставить `DNS` в адресную строку → загружается страница веб-сервера.

После этого необходимо обновить страницу несколько раз.

Каждый раз отображается строка вида:

```bash
Hello from ip-10-0-12-198.ec2.internal
```

![image](https://i.imgur.com/c0pTiiN.png)

или любой другой ip:

![image](https://i.imgur.com/CVgNoC9.png)

> **Вопрос:**
>
> Какие IP-адреса вы видите при обновлении страницы `Load Balancer` и почему они меняются?
>
> **Ответ:**
>
> При обновлении страницы видно **разные приватные IP-адреса** вида
> `ip-10-0-12-198.ec2.internal`, `ip-10-0-11-58.ec2.internal` и другие.
>
> Эти IP-адреса принадлежат **разным EC2-инстансам**, которые были развернуты Auto Scaling Group и привязаны к Target Group.
>
> Они меняются потому, что **Application Load Balancer распределяет входящие запросы между всеми здоровыми инстансами**, обычно по алгоритму *round-robin*.
>
> Поэтому каждый новый запрос может попадать на другой сервер, и на странице отображается его внутренний IP-адрес.

Тестирование подтвердило, что:

- Load Balancer работает корректно
- Запросы распределяются между двумя EC2
- Target Group определяет оба инстанса как **Healthy**
- Auto Scaling + ALB функционируют как единая система

#### 8.3. Подготовка `load.php` для генерации нагрузки

Чтобы `Auto Scaling` мог реагировать на высокую нагрузку, на каждом EC2 является заранее установленный простой PHP-скрипт `load.php`, который выполняет бесконечные вычисления для загрузки CPU.

Этот файл автоматически разворачивается через **User Data**, но при необходимости его можно просмотреть вручную:

**`/var/www/html/load.php`**

Скрипт принимает параметр `seconds` и выполняет тяжёлые операции внутри цикла:

```php
<?php
$seconds = isset($_GET['seconds']) ? intval($_GET['seconds']) : 10;

$end = time() + $seconds;

while (time() < $end) {
    sqrt(rand());
}

echo "CPU load generated for $seconds seconds";
?>
```

![image](https://i.imgur.com/3jNLgN5.png)

- создаёт 100% загрузку CPU на заданное количество секунд
- используется для тестирования `AlarmHigh`, `AlarmLow` и автоматического масштабирования
- вызывается через ссылку:

```
http://ALB-DNS/load?seconds=60
```

### Шаг 9. Тестирование `Auto Scaling`

После создания политики `Target Tracking` для `Auto Scaling Group` необходимо убедиться, что масштабирование действительно работает — новые инстансы создаются при высокой нагрузке, а затем удаляются при снижении нагрузки.

#### 9.1. Проверка созданной политики `Target Tracking`

Необходимо перейти по пути:

**`EC2 → Auto Scaling Groups → project-auto-scaling-group → Automatic Scaling`**

На экране видно, что политика была успешно создана:

- **Policy type:** Target tracking scaling
- **Metric type:** Average CPUUtilization
- **Target value:** 50%
- **Instance warmup:** 300 сек

![image](https://i.imgur.com/USJPRNM.png)

![image](https://i.imgur.com/ulJ6Dgb.png)

#### 9.2. Проверка `CloudWatch Alarms` перед нагрузкой

Необходимо перейти по пути:

**`CloudWatch → Alarms`**

До нагрузки есть два аварийных правила:

| Alarm         | Условие                                                    | Статус |
| ------------- | ---------------------------------------------------------- | ------ |
| **AlarmHigh** | CPUUtilization > 50% for 3 datapoints within 3 minutes     | OK     |
| **AlarmLow**  | CPUUtilization < 37.5% for 15 datapoints within 15 minutes | OK     |

![image](https://i.imgur.com/FmMD7mp.png)

Это означает — система готова реагировать на рост или падение нагрузки.

#### 9.3. Текущий график CPU до нагрузки

Необходимо перейти по пути:

**`CloudWatch → Metrics → EC2 → By Auto Scaling Group`**

До нагрузки график практически ровный:

- CPUUsage ≈ **0.092% — 1%**
- Никаких пиков нет

> график CPUUtilization ровный около нуля

Это нормальное состояние — система простаивает.

#### 9.4. Генерация высокой нагрузки

Чтобы вызвать `Auto Scaling`, нужно создать нагрузку на веб-серверы.

##### Вариант 1 — нагрузка через браузер

Необходимо открыть ссылку:

```
http://project-alb-1356575818.us-east-1.elb.amazonaws.com/load?seconds=60
```

Несколько вкладок создают непрерывную нагрузку.

![image](https://i.imgur.com/rka98wz.png)

> страница 504 Gateway Time-out — это нормально, нагрузка слишком высокая

#### Вариант 2 — нагрузка через скрипт

Для специализации DevOps необходимо _модифицировать скрипт_ `curl.sh` так, чтобы он:

- принимал параметры из командной строки: количество потоков и длительность нагрузки.
- (дополнительно) использовал `ab` (Apache Benchmark) или `hey` для создания нагрузки вместо бесконечного цикла с `curl`.

```sh
#!/usr/bin/env bash
set -euo pipefail

# ALB DNS
ALB_DNS="project-alb-1356575818.us-east-1.elb.amazonaws.com"

# Настройки нагрузки
THREADS=${1:-10}         # если не передать параметр — будет 10 потоков
SECONDS_LOAD=${2:-60}    # если не передать параметр — будет 60 секунд
TOOL=${3:-curl}          # по умолчанию: curl

TARGET="http://${ALB_DNS}/load?seconds=${SECONDS_LOAD}"

echo "========================================="
echo " Target:   ${TARGET}"
echo " Threads:  ${THREADS}"
echo " Seconds:  ${SECONDS_LOAD}"
echo " Tool:     ${TOOL}"
echo "========================================="

case "${TOOL}" in
  curl)
    echo "[*] Generating load with curl (infinite loop per thread)..."
    for i in $(seq 1 "${THREADS}"); do
      (
        while true; do
          curl -s "${TARGET}" > /dev/null
        done
      ) &
    done
    echo "Load started. Press CTRL+C to stop."
    wait
    ;;

  ab)
    if ! command -v ab >/dev/null 2>&1; then
      echo "Error: 'ab' is not installed."
      exit 1
    fi
    echo "[*] Generating load with ab..."
    TOTAL=$(( THREADS * 100 ))
    ab -n "${TOTAL}" -c "${THREADS}" "${TARGET}/"
    ;;

  hey)
    if ! command -v hey >/dev/null 2>&1; then
      echo "Error: 'hey' is not installed."
      exit 1
    fi
    echo "[*] Generating load with hey..."
    hey -z "${SECONDS_LOAD}s" -c "${THREADS}" "${TARGET}"
    ;;

  *)
    echo "Unknown tool '${TOOL}'. Use: curl | ab | hey"
    exit 1
    ;;
esac
```

Необходимо запустить `curl.sh`:

```sh
./curl.sh project-alb-1356575818.us-east-1.elb.amazonaws.com 10 60 curl
```

- 10 потоков
- каждый нагружает CPU 60 секунд

![image](https://i.imgur.com/osZSJsc.png)

#### 9.5. Резкий рост `CPU Utilization`

Через 1–2 минуты после начала нагрузки CPU резко вырос:

- Пики доходят до **80–100%**
- График оказался выше красной линии (**50%**) — порог `AlarmHigh`

#### 9.6. Срабатывание `AlarmHigh` (Scale-Out)

Когда CPU выше 50% держится 3 точки по 1 минуте → `AlarmHigh` становится:

Красным **In alarm**

![image](https://i.imgur.com/TCGFOf1.png)

Это означает:

- высокая нагрузка подтверждена
- Target Tracking запускает масштабирование **Scale-Out**
- Auto Scaling поднимает новые EC2-инстансы

#### 9.7. Масштабирование: запуск новых EC2-инстансов

Необходимо перейти по пути:

**`EC2 → Instances`**

- До нагрузки в ASG было: **2 инстанса**
- После нагрузки Auto Scaling увеличил их число до **5**

![image](https://i.imgur.com/3RCv09b.png)

#### 9.8. Окончание нагрузки — `AlarmLow → Scale-In`

После завершения нагрузки:

- CPU упал ниже **37.5%**
- AlarmLow перешёл в статус **In alarm**

![image](https://i.imgur.com/iJOobLJ.png)

> AlarmLow был красный → стал зелёный → OK

- Auto Scaling начал уменьшать количество инстансов

![image](https://i.imgur.com/knELQkN.png)

>**Вопрос:**
>
>Какую роль в этом процессе сыграл Auto Scaling?
>
>**Ответ:**
>
>Auto Scaling автоматически следил за загрузкой CPU на инстансах и динамически изменял их количество в группе. Когда нагрузка выросла выше целевого порога, Auto Scaling запустил дополнительные EC2-инстансы (scale-out), чтобы обеспечить стабильную работу приложения. После снижения нагрузки Auto Scaling уменьшил количество инстансов (scale-in), возвращая систему к оптимальному размеру. Таким образом, он обеспечил автоматическую адаптацию инфраструктуры под текущую нагрузку без вмешательства пользователя.

### Шаг 10. Завершение работы и очистка ресурсов

После успешного тестирования `Load Balancer`, `Auto Scaling Group` и политики масштабирования необходимо завершить работу и удалить все созданные в ходе лабораторной работы ресурсы AWS, чтобы прекратить начисление стоимости.

Очистка среды выполняется поэтапно:
от остановки нагрузки → до удаления VPC.

#### 10.1. Остановка нагрузочного теста

Если нагрузка создавалась через:

- браузер — **закрыть все вкладки** `…/load?seconds=60`
- скрипт `curl.sh` — нажать:

**`CTRL + C`**

Тем самым процесс нагрузки завершается.

#### 10.2. Удаление `Load Balancer`

Необходимо перейти по пути:

**`EC2 → Load Balancers → project-alb → Actions → Delete`**

После подтверждения появляется сообщение об успешном удалении:

![image](https://i.imgur.com/Z5hxIoT.png)

#### 10.3. Удаление `Target Group`

Необходимо перейти по пути:

**`EC2 → Target Groups → project-target-group → Actions → Delete`**

После удаления:

![image](https://i.imgur.com/Xd3fB4G.png)

#### 10.4. Завершение всех EC2-инстансов

Необходимо перейти по пути:

**`EC2 → Instances`**

Выбрать все инстансы:

- рабочие EC2
- инстансы, созданные Auto Scaling Group

Выбрать:

**`Instance State → Terminate`**

После завершения статус меняется на **Terminated**:

![image](https://i.imgur.com/LBHCo6m.png)

![image](https://i.imgur.com/Vw6nouF.png)

#### 10.5. Удаление `Auto Scaling Group`

Необходимо перейти по пути:

`*EC2 → Auto Scaling Groups → project-auto-scaling-group → Delete`**

После удаления группа пропадает из списка:

![image](https://i.imgur.com/ufXOnAC.png)

#### 10.6. Удаление `AMI` и `Snapshot`

Необходимо перейти по пути:

**`EC2 → AMIs`**

Выбрать созданную AMI → `Deregister`
Отметить галочку **Delete snapshots** → подтвердить.

Сообщение об удалении:

![image](https://i.imgur.com/9mrZPZ6.png)

#### 10.7. Удаление Launch Template

Необходимо перейти по пути:

**`EC2 → Launch Templates → project-launch-template → Delete`**

Результат:

![image](https://i.imgur.com/wN2RjBd.png)

#### 10.8. Удаление подсетей

Необходимо перейти по пути:

**`VPC → Subnets`**

Удалить все подсети, созданные вручную (public + private).

После удаления появляется сообщение:

![image](https://i.imgur.com/xwYdJOb.png)

#### 10.9. Удаление VPC

Необходимо перейти по пути:

**`VPC → Your VPCs → lab6-vpc → Delete VPC`**

Будут удалены:

- Internet Gateway
- Route Tables
- Network ACLs
- Subnets
- Security Groups

После удаления:

![image](https://i.imgur.com/jJVIMIx.png)

#### Итог

Все созданные в ходе лабораторной работы ресурсы были успешно удалены:

- Load Balancer
- Target Group
- Auto Scaling Group
- EC2 Instances
- AMI + Snapshot
- Launch Template
- Subnets
- VPC

AWS перестаёт начислять стоимость, среда очищена.

## Вывод

В ходе лабораторной работы была развернута полноценная масштабируемая веб-инфраструктура на AWS, включающая VPC, подсети, балансировщик нагрузки, шаблон запуска, `Auto Scaling Group` и политику динамического масштабирования. На основе созданного AMI были автоматически развернуты веб-серверы, распределённые между `Availability Zones` для повышения отказоустойчивости. После настройки политики `Target Tracking` была выполнена нагрузка на систему, что вызвало рост загрузки `CPU` и запуск дополнительных `EC2`-инстансов. Это подтвердило корректную работу `Auto Scaling` в режиме `scale-out` и его способность автоматически адаптироваться под высокие нагрузки. После прекращения нагрузки система самостоятельно сократила количество инстансов до минимального, продемонстрировав корректный `scale-in`. Завершением работы стало удаление всех созданных ресурсов, что обеспечило полную очистку окружения и исключило дальнейшие расходы. В результате была отработана практика автоматического масштабирования и управления облачной инфраструктурой, что является ключевым навыком в DevOps и Cloud-инженерии.

## Библиография

1. **[Amazon EC2 Documentation](https://docs.aws.amazon.com/ec2/index.html)** — официальная документация по работе с виртуальными машинами **Amazon EC2**, AMI, Launch Templates, сетевой конфигурацией и жизненным циклом инстансов.
2. **[Elastic Load Balancing Documentation](https://docs.aws.amazon.com/elasticloadbalancing/index.html)** — руководство по созданию и настройке **Application Load Balancer**, target groups, listeners и распределению трафика между EC2-инстансами.
3. **[Amazon CloudWatch Documentation](https://docs.aws.amazon.com/cloudwatch/index.html)** — документация по мониторингу AWS-ресурсов, настройке метрик, графиков загрузки CPU, тревог (Alarms) и интеграции с Auto Scaling.
4. **[Amazon VPC Documentation](https://docs.aws.amazon.com/vpc/index.html)** — справочник по созданию **VPC**, подсетей, маршрутов, Internet Gateway, Security Groups и сетевой архитектуре, использованной для развертывания приложения.
5. **[Amazon Auto Scaling Documentation](https://docs.aws.amazon.com/autoscaling/index.html)** — официальное руководство по настройке **Auto Scaling Group**, политик масштабирования (Target Tracking), параметра warm-up и автоматическому scale-in/scale-out.

