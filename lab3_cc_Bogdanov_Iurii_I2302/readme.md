# Лабораторная работа №3. Облачные сети.

## Цели работы

Научиться вручную создавать виртуальную сеть (VPC) в AWS, добавлять в неё подсети, таблицы маршрутов, интернет-шлюз (IGW) и NAT Gateway, а также настраивать взаимодействие между веб-сервером в публичной подсети и сервером базы данных в приватной.

После выполнения работы студент:

- понимает, как формируется изоляция сетей в AWS (VPC);
- умеет создавать и связывать компоненты сети;
- знает, как EC2-инстансы разных подсетей взаимодействуют друг с другом;
- различает публичные и приватные маршруты.

## Условия

_Amazon VPC (Virtual Private Cloud)_ — это собственная виртуальная сеть в облаке AWS.
Она полностью изолирована от других пользователей и позволяет управлять адресным пространством, подсетями, шлюзами и безопасностью.

В типичном сценарии есть:

- _Публичная подсеть_. Для веб-сервера (имеет выход в интернет).
- _Приватная подсеть_. Для базы данных (без прямого доступа извне).
- _NAT Gateway_. Чтобы приватные ресурсы имели доступ в интернет (например, для обновления ПО).
- _Route Tables_. Определяют, куда направлять трафик.
- _Security Groups_. Управляют входящими и исходящими соединениями на уровне инстансов.
- _EC2-инстансы_. Веб-сервер, сервер базы данных и bastion host.

## Ход выполнения работы

### Шаг 1. Подготовка среды

1. Войти в AWS Management Console.
2. Убедиться, что регион установлен на `Frankfurt` (eu-central-1).

![image](https://i.imgur.com/HSfZFlO.png)

3. В строке поиска ввести _VPC_ и открыть консоль.

![image](https://i.imgur.com/3go9Au4.png)

### Шаг 2. Создание VPC

1. В левой панели необходимо выбрать `Your VPCs` → `Create VPC`.
2. Указать:
   - `Name tag`: `student-vpc-kXX` (где `XX` — порядковый номер).

   - `IPv4 CIDR block`: `10.(k%30).0.0/16`

      > Пример: если `k = 12`, использовать `10.12.0.0/16`. Если `k = 31`, использовать `10.1.0.0/16`.

   - `Tenancy`: Default

3. Нажать `Create VPC`.

![image](https://i.imgur.com/hcZmiEj.png)
![image](https://i.imgur.com/siAelWu.png)

_VPC_ — это “контейнер” для подсетей. Внутри одной VPC можно создавать десятки подсетей с разными маршрутами и правилами.

> **Вопрос:** Что обозначает маска `/16`? И почему нельзя использовать, например, `/8`?
>
> **Ответ:** Маска **/16** означает, что первые 16 бит адреса используются для обозначения сети, а оставшиеся — для устройств внутри неё. Это даёт 65 536 возможных IP-адресов, что достаточно для небольшой облачной сети. Маску **/8** использовать нельзя, потому что она создаёт слишком большую сеть (около 16 миллионов адресов), что нарушает ограничения AWS и усложняет управление ресурсами.

### Шаг 3. Создание Internet Gateway (IGW)

Internet Gateway позволяет ресурсам внутри VPC выходить в Интернет. _Без него публичные IP-адреса не будут работать_. Если виртуальной машине (EC2) назначен публичный IP, но нет IGW, она не сможет общаться с внешним миром.

1. В левой панели необходимо выберать `Internet Gateways` → `Create internet gateway`.
2. Указать имя: `student-igw-kXX`.

![image](https://i.imgur.com/gFxKZzc.png)
![image](https://i.imgur.com/Hj8gFUW.png)
![image](https://i.imgur.com/UqvLOsS.png)

3. Теперь нужно “прикрепить” (Attach) шлюз к сети:
   - Выберать созданный IGW.
   - Нажать `Actions` → `Attach to VPC`.
   - В списке выбрать `student-vpc-kXX`.
   - Подтвердить действие.

![image](https://i.imgur.com/IMqYL4B.png)
![image](https://i.imgur.com/dlpDswr.png)
![image](https://i.imgur.com/na1wy1f.png)

### Шаг 4. Создание подсетей

_Подсети (subnets)_ — это сегменты внутри VPC, которые позволяют изолировать ресурсы. То есть, подсети создаются для разделения ресурсов по функционалу и уровню доступа и для более гибкого управления трафиком.

#### Шаг 4.1. Создание публичной подсети

Теперь, когда есть VPC и Internet Gateway, необходимо создать первую подсеть — публичную.
Эта подсеть будет содержать ресурсы, которым нужен прямой доступ из Интернета.

1. В левой панели необходимо выберать `Subnets` → `Create subnet`.
2. Указать:
   - `VPC ID`: выберать сеть `student-vpc-kXX`
   - `Subnet name`: `public-subnet-kXX`
   - `Availability Zone`: `eu-central-1a`
      > AWS создаёт подсети в конкретных зонах доступности; в данном случае необходимо выбрать первую
   - `IPv4 CIDR block`: `10.(k%30).1.0/24`
      > Диапазон IP-адресов, которые будут выданы ресурсам в этой подсети
3. Нажать `Create subnet`.

![image](https://i.imgur.com/RfclYEE.png)
![image](https://i.imgur.com/E7CLLGC.png)

> **Вопрос:** Является ли подсеть «публичной» на данный момент? Почему?
>
> **Ответ:** Нет, пока нет. Подсеть считается публичной только после того, как в её таблицу маршрутов добавлен маршрут в интернет через Internet Gateway (IGW). Сейчас она изолирована внутри VPC.

#### Шаг 4.2. Создание приватной подсети

Подсеть называется приватной, если её трафик не направляется напрямую в Интернет.

1. Необходимо нажать `Create subnet` ещё раз.
2. Указать:
   - `VPC ID`: выбрать сеть `student-vpc-kXX`
      > Используется та же VPC, чтобы обе подсети могли взаимодействовать между собой.
   - `Subnet name`: `private-subnet-kXX`
   - `Availability Zone`: _Выбрать любую другую зону_
   - `IPv4 CIDR block`: `10.(k%30).2.0/24`
      > Диапазон адресов не должен пересекаться с диапазоном публичной подсети.
3. Нажать `Create subnet`.

![image](https://i.imgur.com/eXNoqvf.png)
![image](https://i.imgur.com/hAQPFgO.png)

> **Вопрос:** Является ли подсеть «приватной» на данный момент? Почему?
>
> **Ответ:** Пока нет. Подсеть становится приватной только после того, как в её таблице маршрутов **отсутствует маршрут через IGW** (только локальные маршруты). Сейчас это просто изолированная подсеть без выхода в интернет.

### Шаг 5. Создание таблиц маршрутов (Route Tables)

Теперь, когда есть две подсети (публичная и приватная), необходимо настроить маршруты (Route Tables), которые определяют, как сетевой трафик будет двигаться внутри нашей VPC.

По умолчанию каждая новая VPC имеет одну основную таблицу маршрутов, и все новые подсети автоматически к ней подключаются. Если зайти в `Route Tables`, можно увидеть одну таблицу, связанную с VPC.

Но для лучшей структуры и изоляции необходимо создать:

- отдельную таблицу маршрутов для публичной подсети (с доступом к Интернету через IGW),
- отдельную таблицу маршрутов для приватной подсети (с доступом к Интернету через NAT Gateway).

#### Шаг 5.1. Создание публичной таблицы маршрутов

1. В левой панели необходимо выберать `Route Tables` → `Create route table`.
2. Указать:
   - `Name tag`: `public-rt-kXX`
   - `VPC`: `student-vpc-kXX`
   - Нажать `Create route table`

![image](https://i.imgur.com/RM7KV4f.png)
![image](https://i.imgur.com/9r2dMtd.png)

   - Перейти на вкладку `Routes` и нажать `Edit routes` → `Add route`.
   - Заполнить:
      - `Destination`: 0.0.0.0/0
         > Это означает “весь остальной трафик, не относящийся к внутренним адресам VPC”.
      - `Target`: выбрать Internet Gateway (`student-igw-kXX`).
   - Нажать `Save changes`.

![image](https://i.imgur.com/1i4XRXk.png)
![image](https://i.imgur.com/s7sgrsG.png)

   - Перейти на вкладку `Subnet associations` → `Edit subnet associations`.
   - Отметить `public-subnet-kXX` и нажать `Save associations`.

![image](https://i.imgur.com/8Y3waoO.png)

Теперь трафик из публичной подсети (например, от веб-сервера или NAT Gateway) будет отправляться наружу через Internet Gateway. Связь `“0.0.0.0/0 → IGW”` — именно то, что делает подсеть публичной.

> **Вопрос:** Зачем необходимо привязать таблицу маршрутов к подсети?
>
> **Ответ:** Без привязки таблицы маршрутов подсеть не будет знать, как направлять трафик. Привязка определяет, какие правила маршрутизации действуют для данной подсети — например, должна ли она иметь доступ к интернету через Internet Gateway или работать только внутри локальной сети VPC.

#### Шаг 5.2. Создание приватной таблицы маршрутов

1. Необходимо нажать `Create route table` ещё раз.
2. Указать:
   - `Name tag`: `private-rt-kXX`
   - `VPC`: `student-vpc-kXX`
   - Нажать `Create route table`.

![image](https://i.imgur.com/s4MW6RK.png)

3. Перейти на вкладку `Subnet associations` → `Edit subnet associations`.
4. Отметить `private-subnet-kXX` и нажать `Save associations`.

![image](https://i.imgur.com/G5Dikyv.png)

На данный момент все ресурсы, которые будут созданы в приватной подсети, не смогут выходить в Интернет, так как на данный момент нет NAT Gateway и соответствующего маршрута.

### Шаг 6. Создание NAT Gateway

NAT Gateway позволяет ресурсам в приватной подсети выходить в Интернет (например, для обновления ПО), при этом оставаясь недоступными извне.

> **Вопрос:** Как работает NAT Gateway?
>
> **Ответ:** NAT Gateway (Network Address Translation Gateway) позволяет ресурсам из приватной подсети выходить в Интернет, не раскрывая свои внутренние IP-адреса. Он принимает запросы от приватных серверов, подменяет их IP на свой публичный адрес и отправляет в сеть. Ответы возвращаются обратно через NAT, и система прозрачно перенаправляет их к исходным машинам в приватной подсети.

#### Шаг 6.1. Создание Elastic IP

_Elastic IP_ — это статический публичный IPv4-адрес, закреплённый за вашим аккаунтом AWS.
Он используется для NAT Gateway, чтобы тот мог представлять собой “точку выхода” в Интернет от имени всех приватных инстансов.

1. В левой панели необходимо выбрать `Elastic IPs` → `Allocate Elastic IP address`.
2. Нажать Allocate.

![image](https://i.imgur.com/DqJrSgD.png)
![image](https://i.imgur.com/HRGIp4J.png)

#### Шаг 6.2. Создание NAT Gateway

1. В левой панели необходимо выбрать `NAT Gateways` → `Create NAT gateway`.
2. Указать:
   - `Name tag`: `nat-gateway-kXX`
   - `Subnet`: выбрать публичную подсеть (`public-subnet-kXX`)
      > NAT Gateway всегда создаётся в публичной подсети, потому что ему нужен прямой выход в Интернет через IGW.
   - `Connectivity type`: `Public`
   - `Elastic IP allocation ID`: выбрать EIP, созданный на предыдущем шаге.
3. Нажать `Create NAT gateway`.

![image](https://i.imgur.com/gofUNA2.png)

Подождать 2–3 минуты, пока статус изменится с `Pending` на `Available`. Это значит, что NAT Gateway готов к работе.

![image](https://i.imgur.com/oeffvE4.png)

#### Шаг 6.3. Изменение приватной таблицы маршрутов

1. Вернуться в `Route Tables` и выбрать `private-rt-kXX`.
2. Перейти на вкладку `Routes` и нажать `Edit routes` → `Add route`.
3. Заполнить:
   - `Destination`: `0.0.0.0/0`
   - `Target`: выбрать NAT Gateway (`nat-gateway-kXX`).
4. Нажать `Save changes`.

![image](https://i.imgur.com/NbjthJr.png)
![image](https://i.imgur.com/jJfI2J2.png)

Теперь ресурсы в приватной подсети смогут выходить в Интернет через NAT Gateway.

### Шаг 7. Создание Security Groups

_Security Group (SG)_ — это виртуальный брандмауэр на уровне инстанса (EC2), который контролирует входящий (Inbound) и исходящий (Outbound) трафик.

1. В левой панели необходимо выбрать `Security Groups` → `Create security group`.
2. Укажите:
   - `Security group name`: `web-sg-kXX`
   - `Description`: `Security group for web server`
   - `VPC`: выбрать VPC `student-vpc-kXX`
3. В разделе Inbound rules добавить правила разрешающее следующие типы трафика:
   - Тип: `HTTP`, Протокол: `TCP`, Порт: `80`, Источник: `0.0.0.0/0`
   - Тип: `HTTPS`, Протокол: `TCP`, Порт: `443`, Источник: `0.0.0.0/0`

![image](https://i.imgur.com/8XHJvFA.png)
![image](https://i.imgur.com/TPC6gjl.png)

4. Создать еще две Security Groups:
   - `bastion-sg-kXX` для bastion host с разрешением входящего трафика на порт `22` (SSH) только из IP-адреса студента.
   - `db-sg-kXX` для базы данных с разрешением входящего трафика:
      - Тип: `MySQL/Aurora`, Протокол: `TCP`, Порт: `3306`, Источник: `web-sg-kXX` (разрешить доступ только с веб-сервера)
      - Тип: `SSH`, Протокол: `TCP`, Порт: `22`, Источник: `bastion-sg-kXX` (разрешить доступ только с bastion host)

![image](https://i.imgur.com/ltxRGSs.png)
![image](https://i.imgur.com/6azhcQf.png)
![image](https://i.imgur.com/9GfC8GG.png)
![image](https://i.imgur.com/JO0Ki97.png)

> **Вопрос:** Что такое *Bastion Host* и зачем он нужен в архитектуре с приватными подсетями?
>
> **Ответ:** *Bastion Host* — это специальный сервер, размещённый в публичной подсети и защищённый правилами безопасности. Он служит “точкой входа” для администраторов, которые хотят подключиться к ресурсам в приватных подсетях. Через него можно безопасно получить SSH-доступ к внутренним серверам, не открывая приватные подсети напрямую в Интернет.

### Шаг 8. Создание EC2-инстансов

Необходимо создать три EC2-инстанса, которые будут выполнять следующие роли:

- _Веб-сервер_ (`web-server`) - в публичной подсети, доступен из Интернета по HTTP.
- _Сервер базы данных_ (`db-server`) - в приватной подсети, недоступен напрямую извне.
- _Bastion Host_ (`bastion-host`) - в публичной подсети, для безопасного доступа к приватным ресурсам.

1. В строке поиска AWS Console ввести `EC2` и открыть консоль.
2. Создать 3 инстанса, следуя инструкциям ниже.

_Для всех инстансов использовать_:

- AMI: `Amazon Linux 2 AMI (HVM), SSD Volume Type`
- Тип инстанса: `t3.micro`
- Ключ доступа (Key Pair): создать новый ключ `student-key-kXX` и скачать его.
- Хранилище: оставить по умолчанию (8 ГБ).
- Теги: добавить тег `Name` с соответствующим именем инстанса.

![image](https://i.imgur.com/qyJqSjb.png)

Для `bastion-host`:

1. Выбрать сеть `VPC`: `student-vpc-kXX`
2. Подсеть `Subnet`: `public-subnet-kXX`
3. `Auto-assign Public IP`: `Enable`
4. `Security Group`: выберать `bastion-sg-kXX`
5. В разделе `Advanced Details` в поле `User data` вставить следующий скрипт для автоматической установки MySQL клиента:

   ```bash
   #!/bin/bash
   dnf install -y mariadb105
   ```

![image](https://i.imgur.com/amRGtBd.png)
![image](https://i.imgur.com/S2vvWdg.png)
![image](https://i.imgur.com/qses0tn.png)
![image](https://i.imgur.com/9oIpAVK.png)

Для `web-server`:

1. Выберать сеть `VPC`: `student-vpc-kXX`
2. Подсеть `Subnet`: `public-subnet-kXX`
3. `Auto-assign Public IP`: `Enable`
4. `Security Group`: выберать `web-sg-kXX`
5. В разделе `Advanced Details` в поле `User data` вставить следующий скрипт для автоматической установки веб-сервера:

   ```bash
   #!/bin/bash
   dnf install -y httpd php
   echo "<?php phpinfo(); ?>" > /var/www/html/index.php
   systemctl enable httpd
   systemctl start httpd
   ```

![image](https://i.imgur.com/r1Xgztz.png)
![image](https://i.imgur.com/qAEJJ0g.png)
![image](https://i.imgur.com/le1kHIM.png)
![image](https://i.imgur.com/ABCVXG2.png)

Для `db-server`:

1. Выбрать сеть `VPC`: `student-vpc-kXX`
2. Подсеть `Subnet`: `private-subnet-kXX`
3. `Auto-assign Public IP`: `Disable`
4. `Security Group`: выберать `db-sg-kXX`
5. В разделе `Advanced Details` в поле `User data` вставить следующий скрипт для автоматической установки MySQL сервера:

   ```bash
   #!/bin/bash
   dnf install -y mariadb105-server
   systemctl enable mariadb
   systemctl start mariadb
   mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'StrongPassword123!'; FLUSH PRIVILEGES;"
   ```

![image](https://i.imgur.com/8kwzSs3.png)
![image](https://i.imgur.com/RnTKqHC.png)
![image](https://i.imgur.com/YiDTfQY.png)
![image](https://i.imgur.com/oMCl9yW.png)

### Шаг 9. Проверка работы

На этом этапе уже созданы:

- виртуальная сеть (VPC)
- публичная и приватная подсети
- интернет-шлюз (IGW)
- NAT Gateway
- две таблицы маршрутов
- три экземпляра EC2 (Web, DB и Bastion)
- три Security Group

Теперь важно убедиться, что сеть функционирует корректно и что приватная подсеть действительно изолирована от внешнего мира.

1. Необходимо подождать, пока все инстансы запустятся (статус `running`).
2. Найти публичный IP-адрес `web-server` и открыть его в браузере. Должна появиться страница с информацией о PHP.

![image](https://i.imgur.com/Alvs7QM.png)

3. Необходимо подключититься к `bastion-host` по SSH:

   ```bash
   ssh -i <your-nickname>-key.pem ec2-user@<Bastion-Host-Public-IP>
   ```

![image](https://i.imgur.com/SfvuRNE.png)

4. Проверить подключение к интернету с `bastion-host` выполнив `ping`:

   ```bash
      ping -c 4 google.com
   ```

   > Если пинги успешны, значит публичная подсеть и IGW настроены правильно.

![image](https://i.imgur.com/So17qnB.png)

5. С `bastion-host` попробовать подключиться к `db-server`

Перед подключением к экземпляру EC2 необходимо убедиться, что приватный ключ `.pem` имеет правильные права доступа.
Если права слишком открытые, `SSH` не позволит подключиться.

```bash
chmod 400 student-key.pem
```

Команда делает файл доступным только для чтения владельцем.
Это требование системы безопасности `AWS` — иначе подключение будет отклонено как небезопасное.

После этого необходимо установить и настроить сервер базы данных `MariaDB`.

Для этого через Bastion Host выполняется подключение к приватному серверу по SSH и установка пакета:

```bash
sudo dnf install -y mariadb105-server
sudo systemctl enable --now mariadb
sudo systemctl status mariadb
```

Если служба MariaDB работает, её статус отображается как `active (running)`.

После установки MariaDB и запуска службы можно убедиться, что она слушает порт 3306 (порт по умолчанию для MySQL/MariaDB).
Для этого используется команда:

```bash
sudo ss -ltnp | grep 3306
```

![image](https://i.imgur.com/Sj8TCHp.png)

Далее выполняется подключение к базе данных под пользователем `root` и создание отдельного пользователя для работы приложения.

```bash
mysql -u root -p
```

![image](https://i.imgur.com/zvBiSR5.png)
![image](https://i.imgur.com/hQdfJeZ.png)

После входа в консоль MariaDB создаётся пользователь `lab`, которому разрешено подключаться из подсетей `10.*.*.*` (внутренняя сеть VPC):

```sql
CREATE USER 'lab'@'10.%' IDENTIFIED BY 'StrongPassword123!';
GRANT ALL PRIVILEGES ON *.* TO 'lab'@'10.%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EXIT;
```

После успешного подключения к Bastion Host необходимо проверить доступность базы данных, расположенной в приватной подсети.

Для этого выполняется подключение к MariaDB с использованием созданного пользователя `lab`:

   ```bash
   mysql -h 10.1.2.20 -u lab -p
   ```

![image](https://i.imgur.com/4eF3xON.png)

Успешное подключение к MariaDB через Bastion Host подтверждает корректную работу маршрутов, NAT Gateway и Security Groups.

6. Выйти из `db-server` и `bastion-host`.

### Шаг 10. Дополнительные задания. Подключение в приватную подсеть через Bastion Host

Так как приватная подсеть не имеет выхода в интернет, подключение к `db-server` выполняется через промежуточный сервер — `bastion-host`.

1. На локальной машине необходимо выполнить следующие команды. Это запустит SSH Agent и добавит приватный ключ в агент:

В PowerShell необходимо запустить службу SSH Agent и добавить приватный ключ:

```bash
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add .\student-key-k1.pem
```

2. Необходимо подключиться к bastion-host с опцией `-A` и `-J`:

Подключение выполняется с опциями `-A` и `-J`, которые позволяют использовать переадресацию `SSH`-ключа и указать промежуточный хост:

```bash
ssh -A -J ec2-user@3.123.128.242 ec2-user@10.1.2.20
```

`-A` — включает переадресацию ключей (Agent Forwarding);

`-J` — указывает bastion как промежуточный узел.

![image](https://i.imgur.com/yVWNOfY.png)

3. Обновить систему на `db-server`:

```bash
sudo dnf update -y
```

4. Установить `htop`:

```bash
sudo dnf install -y htop
```

> Если обновление и установка прошли успешно, значит `NAT Gateway` работает корректно.

![image](https://i.imgur.com/RM7CsHi.png)

5. Подключиться к `MySQL` серверу:

```bash
mysql -u root -p
```

![image](https://i.imgur.com/AR7axSA.png)

> Если `MySQL` не установлен, выполните `sudo dnf install -y mariadb105`. Пароль `StrongPassword123!`.

6. Выйти из `MySQL` и затем из `db-server` и `bastion-host`.

7. На локальном компьютере, завершить работу с `SSH Agent`:

```bash
ssh-add -D
Stop-Service ssh-agent
```

## Завершение работы

После выполнения всех шагов, необходимо удалить созданные ресурсы в `AWS`, чтобы избежать ненужных затрат. Выполнить удаление в следующем порядке:

1. Удалить `EC2`-инстансы.

![image](https://i.imgur.com/rXHUkmA.png)

2. Удалить `NAT Gateway` (подождите, пока он будет удалён).

![image](https://i.imgur.com/7QMZHr5.png)

3. Удалить `Elastic IP`.

   - `VPC` -> `Elastic IPs` -> выберать `EIP` -> `Actions` -> `Release Elastic IP addresses`.

![image](https://i.imgur.com/Y6990LO.png)

4. Удалить `Security Groups`.

   - `VPC` -> `Security Groups` -> выберать нужную группу -> `Actions` -> `Delete Security Group`.

![image](https://i.imgur.com/P3VTruc.png)

5. Удалить `Internet Gateway`.

   - `VPC` -> `Internet Gateways` -> выберать `IGW` -> `Actions` -> `Detach from VPC` -> подтвердить.
   - Затем снова выберать IGW -> `Actions` -> `Delete internet gateway`.

![image](https://i.imgur.com/weNxyew.png)
![image](https://i.imgur.com/n2qekV6.png)

6. Удалить созданную `VPC`.

   - `VPC` -> `Your VPCs` -> выберите вашу VPC -> `Actions` -> `Delete VPC`.
   - Подтвердите удаление.
   - Если удаление не удаётся, проверьте, что все ресурсы (подсети, таблицы маршрутов и т.д.) были удалены.

![image](https://i.imgur.com/2TCt9b2.png)

> Удаление ресурсов в неправильном порядке может привести к ошибкам, так как некоторые ресурсы зависят от других.

Для того, чтобы кредиты не снимались достаточно удалить `EC2` инстансы, `NAT Gateway` и `Elastic IP`. Остальные ресурсы можно оставить, так как они не тарифицируются отдельно.

## Выводы

В ходе выполнения лабораторной работы №3 была вручную создана и настроена облачная сеть (`VPC`) в `AWS`, включающая все необходимые компоненты для безопасного взаимодействия между публичной и приватной подсетями. В процессе работы была создана собственная виртуальная сеть и две подсети — публичная и приватная. Настроен интернет-шлюз (`Internet Gateway`) для организации внешнего доступа и `NAT Gateway`, обеспечивающий безопасный исходящий доступ приватных ресурсов к интернету. Были созданы таблицы маршрутов, определяющие движение сетевого трафика, и группы безопасности (`Security Groups`), регулирующие входящий и исходящий доступ к инстансам.

Были развернуты и проверены `EC2`-инстансы — веб-сервер, база данных и `bastion host`, после чего проведена проверка корректности их взаимодействия, а также работы маршрутизации и `NAT Gateway`. В результате была продемонстрирована полная работа сетевой инфраструктуры в `AWS` и подтверждено понимание принципов построения и изоляции сетей, маршрутизации и обеспечения безопасности на уровне `VPC`.

В ходе выполнения работы были получены практические навыки создания и настройки виртуальной частной сети, подключения к приватным ресурсам через `Bastion Host`, а также понимание принципов взаимодействия публичных и приватных компонентов облачной архитектуры.

## Библиография

1. [AWS Documentation](https://docs.aws.amazon.com/) — официальная документация по сервисам Amazon Web Services.
2. [Amazon VPC User Guide](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html) — руководство пользователя по созданию и настройке виртуальных частных сетей в AWS.
3. [Amazon EC2 User Guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/concepts.html) — руководство пользователя по работе с виртуальными машинами EC2.
4. [AWS NAT Gateway Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html) — официальная документация по созданию и использованию NAT Gateway в AWS.


