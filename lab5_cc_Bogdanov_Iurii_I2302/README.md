# Лабораторная работа №5. Облачные базы данных. Amazon RDS, DynamoDB

## Цель работы

Целью работы является ознакомиться с сервисами `Amazon RDS` (Relational Database Service) и `Amazon DynamoDB`, а также научиться:

- Создавать и настраивать экземпляры реляционных баз данных в облаке AWS с использованием `Amazon RDS`.
- Понимать концепцию `Read Replicas` и применять их для повышения производительности и отказоустойчивости баз данных.
- Подключаться к базе данных `Amazon RDS` с виртуальной машины EC2 и выполнять базовые операции с данными (создание, чтение, обновление, удаление записей - CRUD).
- (_Дополнительно_) Ознакомиться с сервисом `Amazon DynamoDB` и освоить работу с хранением данных в `NoSQL`-формате.

## Ход выполнения работы

### Шаг 1. Подготовка среды (VPC/подсети/SG)

#### 1.1. Создание VPC `project-vpc`

1. Необходимо войти в **AWS Management Console** и в правом верхнем углу выбрать регион
   **Frankfurt (eu-central-1)**.

2. Перейти в сервис **VPC** → пункт **Your VPCs** → нажать **Create VPC**.

3. В мастере выбрать режим:

   - **Resources to create** → `VPC and more`.

4. Заполнить параметры, как показано в таблице:

| Параметр                     | Значение           |
| ---------------------------- | ------------------ |
| Resources to create          | VPC and more       |
| Name tag auto-generation     | project-vpc        |
| IPv4 CIDR block              | 10.0.0.0/16        |
| IPv6 CIDR block              | No IPv6 CIDR block |
| Tenancy                      | Default            |
| Number of Availability Zones | 2                  |
| Number of public subnets     | 2                  |
| Number of private subnets    | 2                  |
| NAT gateways ($)             | None               |
| VPC endpoints                | None               |
| Enable DNS hostnames         | Enabled (галочка)  |
| Enable DNS resolution        | Enabled (галочка)  |

5. Нажать кнопку **Create VPC** и дождаться статуса `Success`.

![image](https://i.imgur.com/sdLQ4ZM.png)
![image](https://i.imgur.com/L1nwSXG.png)
![image](https://i.imgur.com/wLIDz7C.png)
![image](https://i.imgur.com/r0Crt9H.png)

В результате создаётся VPC `project-vpc-vpc` с четырьмя подсетями и интернет-шлюзом.

#### 1.2. Создание группы безопасности `web-security-group` (для приложения)

1. Перейти в сервис **EC2** → пункт **Security Groups** → нажать **Create security group**.
2. Заполнить основные поля по таблице:

| Параметр            | Значение                                                     |
| ------------------- | ------------------------------------------------------------ |
| Security group name | web-security-group                                           |
| Description         | (по желанию) Security group for web application (HTTP + SSH) |
| VPC                 | project-vpc-vpc                                              |

3. В секции **Inbound rules** добавить два правила:

| Type | Protocol | Port range | Source             | Назначение                      |
| ---- | -------- | ---------: | ------------------ | ------------------------------- |
| HTTP | TCP      |         80 | 0.0.0.0/0          | Доступ к веб-приложению из сети |
| SSH  | TCP      |         22 | My IP (x.x.x.x/32) | SSH только с текущего IP        |

4. В секции **Outbound rules** оставить значение по умолчанию:

| Type        | Protocol | Port range | Destination | Комментарий                    |
| ----------- | -------- | ---------: | ----------- | ------------------------------ |
| All traffic | All      |        All | 0.0.0.0/0   | Разрешён весь исходящий трафик |

5. Нажать **Create security group**.

![image](https://i.imgur.com/hOzN4cZ.png)
![image](https://i.imgur.com/I9wW4LM.png)

#### 1.3. Создание группы безопасности `db-mysql-security-group` (для базы данных)

1. В разделе **Security Groups** снова нажать **Create security group**.
2. Заполнить параметры:

| Параметр            | Значение                                  |
| ------------------- | ----------------------------------------- |
| Security group name | db-mysql-security-group                   |
| Description         | (по желанию) Security group for MySQL RDS |
| VPC                 | project-vpc-vpc                           |

3. В секции **Inbound rules** добавить правило для MySQL:

| Type         | Protocol | Port range | Source                      | Назначение                                         |
| ------------ | -------- | ---------: | --------------------------- | -------------------------------------------------- |
| MYSQL/Aurora | TCP      |       3306 | web-security-group (sg-...) | Подключение к БД только с инстансов веб-приложения |

4. В секции **Outbound rules** оставить правило по умолчанию:

| Type        | Protocol | Port range | Destination | Комментарий                     |
| ----------- | -------- | ---------: | ----------- | ------------------------------- |
| All traffic | All      |        All | 0.0.0.0/0   | Разрешён исходящий трафик из БД |

5. Нажать **Create security group**.

![image](https://i.imgur.com/w6hPlIV.png)
![image](https://i.imgur.com/BeNCtnk.png)

#### 1.4. Добавление исходящего правила MySQL для `web-security-group`

1. В списке Security Groups выбрать `web-security-group`.
2. Нажать **Edit outbound rules**.
3. Оставить существующее правило `All traffic → 0.0.0.0/0` и добавить ещё одно:

| Type         | Protocol | Port range | Destination                      | Назначение                    |
| ------------ | -------- | ---------: | -------------------------------- | ----------------------------- |
| MYSQL/Aurora | TCP      |       3306 | db-mysql-security-group (sg-...) | Исходящие запросы к RDS MySQL |

![image](https://i.imgur.com/BEvJuCV.png)
![image](https://i.imgur.com/h1CMVAQ.png)

4. Нажать **Save rules**.

После этого сеть полностью готова: есть VPC с 4 подсетями, интернет-шлюз и две связанные группы безопасности для веб-приложения и базы данных.

### Шаг 2. Развертывание Amazon RDS (MySQL)

#### 2.1. Создание Subnet Group `project-rds-subnet-group`

1. Необходимо открыть сервис **Amazon RDS**, перейти в раздел **Subnet groups** и нажать **Create DB subnet group**.

![image](https://i.imgur.com/GtvaVxD.png)

2. Нужно заполнить параметры, как показано в таблице:

| Параметр           | Значение                                  |
| ------------------ | ----------------------------------------- |
| Name               | project-rds-subnet-group                  |
| Description        | Subnet group for RDS MySQL in project-vpc |
| VPC                | project-vpc-vpc                           |
| Availability Zones | eu-central-1a, eu-central-1b              |
| Subnets            | 2 приватные подсети: private1 и private2  |

3. Нужно нажать **Create**.

![image](https://i.imgur.com/nTuoLAd.png)
![image](https://i.imgur.com/sLLnQTP.png)
![image](https://i.imgur.com/I5WRDOx.png)

В результате создаётся Subnet Group со статусом **Complete**.

> **Вопрос:**
>
> **Что такое Subnet Group? И зачем необходимо создавать Subnet Group для базы данных?**
>
> **Ответ:**
>
> **Subnet Group** — это набор двух и более подсетей в выбранном VPC, расположенных в разных Availability Zones.
>
> Она нужна Amazon RDS для того, чтобы понимать **в каких приватных подсетях разрешено создавать базу данных**.
>
> Зачем она требуется:
>
> - чтобы разместить RDS **в приватных подсетях**, недоступных из интернета;
> - чтобы обеспечить **отказоустойчивость**, размещая ресурсы в разных AZ;
> - чтобы RDS мог корректно создать и управлять инстансом базы.
>
> Без Subnet Group RDS просто не сможет развернуть базу данных внутри VPC.

#### 2.2. Создание экземпляра базы данных Amazon RDS MySQL

1. Необходимо открыть раздел **RDS → Databases → Create database**.

2. В секции **Choose a database creation method** нужно выбрать:

   - **Standard Create**

3. Далее необходимо заполнить параметры по таблице:

| Параметр    | Значение              |
| ----------- | --------------------- |
| Engine type | MySQL Community       |
| Version     | MySQL 8.x             |
| Template    | Free tier             |
| Deployment  | Single-AZ DB instance |

![image](https://i.imgur.com/Jt5t9Rp.png)
![image](https://i.imgur.com/l8gDjWW.png)

#### Настройки (Settings)

| Параметр               | Значение               |
| ---------------------- | ---------------------- |
| DB instance identifier | project-rds-mysql-prod |
| Master username        | admin                  |
| Master password        | (указывается вручную)  |

#### DB instance class

| Параметр       | Значение    |
| -------------- | ----------- |
| Instance class | db.t3.micro |

![image](https://i.imgur.com/aBjTQp7.png)
![image](https://i.imgur.com/yD9wNaw.png)

#### Storage (Хранилище)

| Параметр                   | Значение |
| -------------------------- | -------- |
| Storage type               | gp3      |
| Allocated storage          | 20 GB    |
| Enable storage autoscaling | Enabled  |
| Maximum storage threshold  | 100 GB   |

![image](https://i.imgur.com/lelOEtN.png)

#### Connectivity (Подключение)

| Параметр                     | Значение                 |
| ---------------------------- | ------------------------ |
| Virtual private cloud (VPC)  | project-vpc-vpc          |
| Public access                | No                       |
| DB subnet group              | project-rds-subnet-group |
| Existing VPC security groups | db-mysql-security-group  |
| Availability zone            | No preference            |

![image](https://i.imgur.com/NZz6AqF.png)
![image](https://i.imgur.com/1mrks1v.png)
![image](https://i.imgur.com/52XvZIH.png)

#### Additional configuration

| Параметр                   | Значение                                      |
| -------------------------- | --------------------------------------------- |
| Initial database name      | project_db                                    |
| Enable automated backups   | Enabled                                       |
| Backup retention period    | 1 day                                         |
| Enable encryption          | Отключить                                     |
| Auto minor version upgrade | Disabled                                      |

![image](https://i.imgur.com/2VUBX3Q.png)
![image](https://i.imgur.com/qOTfQ30.png)

После заполнения всех настроек необходимо нажать **Create database**.

#### 2.3. Завершение создания базы данных

После нескольких минут ожидания статус должен измениться на:

- **Available**
- База данных **project-rds-mysql-prod** успешно создана.

![image](https://i.imgur.com/ZN0G0GJ.png)

> Необходимо скопировать `Endpoint` базы данных (он понадобится для подключения).

### Шаг 3. Создание виртуальной машины EC2 для подключения к базе данных

Для подключения к базе данных RDS необходимо создать виртуальную машину EC2 в публичной подсети вашего VPC. Инстанс будет использоваться как клиент, с которого выполняется подключение к MySQL.

1. Нужно открыть **EC2 → Instances → Launch instance**.

2. Заполнить параметры создания инстанса:

| Параметр              | Значение                                        |
| --------------------- | ----------------------------------------------- |
| Name                  | project-ec2-db-client                           |
| AMI                   | Amazon Linux 2023 (Free tier eligible)          |
| Instance type         | t3.micro                                        |
| Key pair              | project-rds-key(создан новый)                   |
| VPC                   | project-vpc-vpc                                 |
| Subnet                | Public subnet (eu-central-1a или eu-central-1b) |
| Auto-assign public IP | Enable                                          |
| Security group        | web-security-group                              |

3. В поле **User data** необходимо указать скрипт установки клиента `MySQL/MariaDB`:

```bash
#!/bin/bash
dnf update -y
dnf install -y mariadb105
```

4. Нужно нажать **Launch instance** и дождаться статуса **Running**.

![image](https://i.imgur.com/HUEtGgT.png)
![image](https://i.imgur.com/6fpNtI5.png)
![image](https://i.imgur.com/3Jdlvsk.png)
![image](https://i.imgur.com/BYsPILr.png)
![image](https://i.imgur.com/H1wlGdc.png)

Созданный EC2-инстанс теперь полностью готов для подключения к базе данных `Amazon RDS` и выполнения дальнейших шагов лабораторной работы.

### Шаг 4. Подключение к базе данных и выполнение базовых операций

1. Нужно подключиться к виртуальной машине EC2 по SSH из локального терминала:

```bash
ssh -i "/e/anul3/Cloud_computing/project-rds-key.pem" ec2-user@<PUBLIC_IP>
```

где `<PUBLIC_IP>` — публичный IP-адрес созданного EC2-инстанса.

2. После входа на сервер необходимо убедиться, что установлен клиент `MariaDB/MySQL`:

```bash
mariadb --version
```

![image](https://i.imgur.com/Q7jwx3N.png)

3. Затем нужно подключиться к базе данных RDS по скопированному ранее endpoint’у:

```bash
mariadb -h <RDS_ENDPOINT> -P 3306 -u admin -p
```

где `<RDS_ENDPOINT>` — endpoint инстанса `project-rds-mysql-prod`.

![image](https://i.imgur.com/OxN1itQ.png)

4. После ввода пароля администратора необходимо выбрать базу данных `project_db` и проверить доступные базы:

**`SHOW DATABASES` — выводит список всех БД в MySQL.**

**`USE project_db`— переключает текущее подключение на выбранную базу.**

```sql
SHOW DATABASES;
USE project_db;
```

![image](https://i.imgur.com/yIAobXz.png)

5. Нужно создать две связанные таблицы `categories` и `todos` со связью `one-to-many` (одна категория — много задач):

Создание таблицы `categories`:

- `id` — автоинкрементный первичный ключ
- `name` — текстовое имя категории

Создание таблицы `todos`:

- `category_id` — внешний ключ, ссылающийся на `categories.id`
- Это создаёт связь одна категория → много задач

```sql
CREATE TABLE categories (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

CREATE TABLE todos (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    title       VARCHAR(255) NOT NULL,
    status      VARCHAR(20)  NOT NULL,
    category_id INT          NOT NULL,
    CONSTRAINT fk_todos_category
        FOREIGN KEY (category_id) REFERENCES categories(id)
);
```

- Таблица `categories` хранит *типы* задач.
- Таблица `todos` хранит *конкретные задачи*.
- `category_id` связывает каждую задачу с категорией (1 категория → много задач).

**Проверка структуры таблиц:**

**`SHOW TABLES` — выводит список всех таблиц в базе.**
**`DESCRIBE` — показывает структуру таблицы (поля, типы, ключи).**

```sql
SHOW TABLES;
DESCRIBE categories;
DESCRIBE todos;
```

![image](https://i.imgur.com/xmNU9Gg.png)

6. Затем необходимо вставить несколько записей в обе таблицы:

**`INSERT INTO categories` —  добавляет три категории.**
**`INSERT INTO todos` —  добавляет задачи с указанием категории через `category_id`.**

**Вставка категорий:**

```sql
INSERT INTO categories (name) VALUES
('Work'),
('Study'),
('Personal');
```

После вставки категории получают ID:

| id | name     |
| -- | -------- |
| 1  | Work     |
| 2  | Study    |
| 3  | Personal |

**Вставка задач:**

```sql
INSERT INTO todos (title, status, category_id) VALUES
('Finish AWS lab report',       'in_progress', 2),
('Prepare for cryptography exam','todo',       2),
('Fix bugs in PHP project',     'todo',        1),
('Go to gym',                   'done',        3),
('Call grandma',                'todo',        3);
```

- Третий столбец (`category_id`) — это **внешний ключ**, указывающий на `categories.id`.
- То есть:

  - `2` → Study
  - `1` → Work
  - `3` → Personal

Например:
`('Finish AWS lab report', 'in_progress', 2)` означает, что задача относится к категории **Study**.

**Проверка, что данные вставились:**

Обычные выборки всех строк из таблиц.

```sql
SELECT * FROM categories;
SELECT * FROM todos;
```

![image](https://i.imgur.com/oUuilNN.png)

7. Для проверки данных нужно выполнить несколько запросов, включая `JOIN` между таблицами:

`JOIN` связывает задачи (`todos`) с категориями по полю `category_id`.

**1. Вывести все задачи вместе с названиями категорий**

```sql
SELECT t.id,
       t.title,
       t.status,
       c.name AS category
FROM todos t
JOIN categories c ON t.category_id = c.id;
```

- `JOIN` объединяет таблицы `todos` и `categories`.
- `t.category_id = c.id` — связь задача → категория.
-  Вместо числового `category_id` выводится текстовое название категории.

 Результат показывает, к какой категории относится каждая задача.

![image](https://i.imgur.com/OLF25VV.png)

**2. Вывести задачи, которые ещё не выполнены**

```sql
SELECT t.id,
       t.title,
       t.status,
       c.name AS category
FROM todos t
JOIN categories c ON t.category_id = c.id
WHERE t.status <> 'done';
```

- Условие `<> 'done'` выводит все задачи, кроме выполненных.
- Это фильтр по статусу.

![image](https://i.imgur.com/1hoAdO6.png)

**3. Вывести только задачи категории “Study”**

```sql
SELECT t.id,
       t.title,
       t.status
FROM todos t
JOIN categories c ON t.category_id = c.id
WHERE c.name = 'Study';
```

- Идёт соединение таблиц.
- Фильтрация по категории: `WHERE c.name = 'Study'`.
- Выводятся только те задачи, которые относятся к учебной категории.

![image](https://i.imgur.com/XPsxfDt.png)

В результате выполнены: подключение к `RDS` настроено, структура базы создана, данные добавлены и получены с помощью запросов с `JOIN`.

### Шаг 5. Создание Read Replica

Для создания реплики необходимо открыть консоль **Amazon RDS**, выбрать основной экземпляр `project-rds-mysql-prod` и в меню **Actions** выбрать пункт **Create read replica**.

![image](https://i.imgur.com/tU1vO95.png)

На этапе настройки следует указать следующие параметры:

| Параметр                   | Значение                        |
| -------------------------- | ------------------------------- |
| DB instance identifier     | project-rds-mysql-read-replica  |
| Engine                     | MySQL Community (как у primary) |
| Instance class             | db.t3.micro                     |
| Storage type               | General Purpose SSD (gp3)       |
| Public access              | No                              |
| VPC security group         | db-mysql-security-group         |
| Enhanced monitoring        | Disabled                        |
| Availability Zone          | No preference                   |
| Auto minor version upgrade | Disabled                        |

![image](https://i.imgur.com/8KXxE2X.png)
![image](https://i.imgur.com/PHMJnhE.png)
![image](https://i.imgur.com/hKmCazG.png)
![image](https://i.imgur.com/J6Q4hjf.png)

После сохранения настроек экземпляр реплики создаётся и после инициализации переходит в состояние **Available**.
У реплики появляется отдельный endpoint, используемый только для чтения.

![image](https://i.imgur.com/0ZCNCGU.png)

#### Подключение к Read Replica

Для проверки работы реплики выполняется подключение с EC2-инстанса:

```bash
mariadb -h project-rds-mysql-read-replica.c7a2w4yiq4ee.eu-central-1.rds.amazonaws.com -P 3306 -u admin -p
```

![image](https://i.imgur.com/K2y3tce.png)

#### Чтение данных на реплике

После подключения выбирается база данных:

```sql
USE project_db;
```

Для получения данных выполняются запросы:

```sql
SELECT * FROM categories;
SELECT * FROM todos;
```

![image](https://i.imgur.com/g3fyVi9.png)

> **Вопрос:**
>
> **Какие данные вы видите? Объясните почему.**
>
> **Ответ:**
>
> На реплике отображаются **точно такие же данные**, что и на основном экземпляре.
> Это происходит благодаря механизму **асинхронной репликации MySQL**, при котором все изменения с primary передаются на реплику.
> Реплика синхронизируется с основным инстансом, поэтому её содержимое полностью совпадает с базой данных primary (с небольшой задержкой).

#### Попытка записи в реплику

Проверка ограничения на запись:

```sql
INSERT INTO categories (name) VALUES ('Replica test');
```

![image](https://i.imgur.com/VbDHj8I.png)

Сервер выдаёт ошибку:

```
ERROR 1290: The MySQL server is running with the --read-only option
```

> **Вопрос:**
>
> **Получилось ли выполнить запись на Read Replica? Почему?**
>
> **Ответ:**
>
> Нет, выполнить запись невозможно.
> Реплика работает в режиме **read-only**, то есть допускает только операции чтения (`SELECT`).
> Это сделано специально: реплика предназначена для распределения нагрузки и ускорения чтения данных, но не для изменений. Все INSERT/UPDATE/DELETE блокируются.

#### Проверка репликации

На основном экземпляре добавляется новая категория:

```sql
INSERT INTO categories (name)
VALUES ('New Category');
```

и новая задача:

```sql
INSERT INTO todos (title, status, category_id)
VALUES ('Task from primary', 'todo', 1);
```

![image](https://i.imgur.com/JHynYk2.png)

На реплике выполняется:

```sql
SELECT * FROM categories;
```

```sql
SELECT * FROM todos;
```

![image](https://i.imgur.com/otF5gYX.png)

> **Вопрос:**
>
> **Отобразилась ли новая запись на реплике? Объясните почему.**
>
> **Ответ:**
>
> Да, новая запись появилась на реплике.
> Это происходит потому, что MySQL Read Replica получает все изменения с primary-инстанса через асинхронный механизм репликации.
> После небольшой задержки реплика синхронизируется и отображает все новые данные, которые были вставлены на основной базе.

**`Read Replica`** используется для масштабирования нагрузки на базу данных.
Она позволяет перенести операции чтения (SELECT) с основного экземпляра на реплику.

Основные случаи, когда `Read Replica` полезна:

- **когда нужно разгрузить основную базу, перенесив все SELECT-запросы на отдельный сервер;**
- **когда приложение испытывает высокую нагрузку по чтению;**
- **когда необходимо выполнять отчёты и аналитические запросы, не влияя на работу основной БД;**
- **когда требуется повысить отказоустойчивость: при сбоях чтение данных можно продолжать с реплики.**

**`Read Replica`** нужна для повышения производительности и стабильности системы за счёт разделения потоков чтения и записи.

### Шаг 6. Подключение приложения к базе данных

#### Шаг 6b. Развертывание PHP-приложения из лабораторной работы 4

Для подключения существующего PHP-приложения «Каталог рецептов» (лабораторная работа по дисциплине «Продвинутая веб-разработка (PHP)») к базе данных Amazon RDS были выполнены следующие действия.

#### 1. Подключение к базе данных Amazon RDS и создание таблицы `recipes`

С EC2-инстанса выполняется подключение к экземпляру MySQL, развёрнутому в Amazon RDS:

```bash
mariadb -h project-rds-mysql-prod.c7a2w4yiq4ee.eu-central-1.rds.amazonaws.com -P 3306 -u admin -p
```

После ввода пароля выбирается рабочая база данных:

```sql
USE project_db;
```

Создаётся таблица `recipes` для хранения основных данных о рецептах:

```sql
CREATE TABLE recipes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    category VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

![img](https://i.imgur.com/SY7dwbC.png)

Эта таблица будет использоваться для операций CRUD над рецептами.

#### 2. Копирование архива с проектом на EC2 и распаковка

С локальной машины архив с готовым проектом передаётся на EC2-инстанс по `scp`:

```bash
scp -i "/e/anul3/Cloud_computing/project-rds-key.pem" \
    lab4_Bogdanov_Iurii_I2302.zip ec2-user@3.127.69.157:/home/ec2-user
```

На сервере выполняется распаковка архива в каталог `project`:

```bash
ls -l
unzip lab4_Bogdanov_Iurii_I2302.zip -d project
```

![image](https://i.imgur.com/6E9A1TA.png)

В результате исходники приложения размещаются по пути:

```text
~/project/lab4_Bogdanov_Iurii_I2302/recipe-book
```

#### 3. Установка Apache и PHP на EC2-инстансе

Для запуска PHP-приложения на EC2 устанавливается веб-сервер Apache и PHP c модулем для MySQL:

```bash
sudo yum install httpd php php-mysqlnd -y
```

![img](https://i.imgur.com/o9b9lpO.png)
![img](https://i.imgur.com/WD5Y9Yv.png)

Затем сервис Apache добавляется в автозагрузку и запускается:

```bash
sudo systemctl enable httpd
sudo systemctl start httpd
sudo systemctl status httpd
```

![img](https://i.imgur.com/DgYL7nX.png)

После этого сервер начинает слушать HTTP-запросы на порту 80.

#### 4. Развёртывание PHP-приложения в каталог веб-сервера

Файлы проекта копируются в стандартный корень веб-сервера `/var/www/html`, назначается владелец `apache` и выставляются корректные права доступа:

```bash
sudo cp -r ~/project/lab4_Bogdanov_Iurii_I2302/recipe-book/* /var/www/html/
sudo chown -R apache:apache /var/www/html
sudo chmod -R 755 /var/www/html
```

После копирования файлов приложение становится доступно по адресу вида  
`http://<PUBLIC_IP>:8080`.  

Чтобы браузер смог подключаться к приложению по этому порту, в группе безопасности
`web-security-group` было добавлено отдельное inbound-правило:

- **Type**: Custom TCP  
- **Port range**: `8080`  
- **Source**: `My IP` (мой внешний адрес)

Это ограничивает доступ к приложению только с моего IP-адреса и повышает безопасность.

![image](https://i.imgur.com/eK965SL.png)

#### 5. Создание таблицы `recipe_steps` и связь «рецепт → шаги»

Для хранения пошаговых инструкций используется отдельная таблица `recipe_steps`, связанная с `recipes` внешним ключом. Таблица создаётся в базе `project_db`:

```sql
CREATE TABLE recipe_steps (
    id INT AUTO_INCREMENT PRIMARY KEY,
    recipe_id INT NOT NULL,
    steps_json TEXT NOT NULL,
    FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE
);

SHOW TABLES;
```

![image](https://i.imgur.com/QCFNQba.png)

Внешний ключ с опцией `ON DELETE CASCADE` гарантирует, что при удалении рецепта из `recipes` связанные шаги автоматически удаляются из `recipe_steps`.

#### 6. Настройка единого подключения к Amazon RDS (файл `src/db.php`)

В каталоге `src` создаётся файл `db.php`, который инкапсулирует подключение к базе Amazon RDS через PDO:

```php
<?php
/**
 * Подключение к базе данных Amazon RDS (MySQL)
 */

$host     = "project-rds-mysql-prod.c7a2w4yiq4ee.eu-central-1.rds.amazonaws.com";
$dbname   = "project_db";
$username = "admin";
$password = "МОЙ_ПАРОЛЬ";

try {
    $pdo = new PDO(
        "mysql:host=$host;dbname=$dbname;charset=utf8",
        $username,
        $password,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );
} catch (PDOException $e) {
    die("Database connection failed: " . $e->getMessage());
}
```

![image](https://i.imgur.com/yZCDNZU.png)

Этот файл затем подключается во всех скриптах, которым нужен доступ к БД:

```php
// на главной странице
require_once __DIR__ . '/../src/db.php';
```

![image](https://i.imgur.com/n1Eh1yn.png)

```php
// на странице со всеми рецептами
require_once __DIR__ . '/../../src/db.php';
```

![image](https://i.imgur.com/6oBG4bX.png)

```php
// в обработчиках формы
require_once __DIR__ . '/../../../src/db.php';
```

![image](https://i.imgur.com/wMpWUDD.png)

Такое решение упрощает поддержку и гарантирует, что всё приложение использует одно и то же подключение к Amazon RDS.

#### 7. Реализация операции Create: сохранение нового рецепта в Amazon RDS

За сохранение отвечает обработчик `public/handlers/save_recipe.php`.
В нём последовательно выполняются следующие шаги:

1. Включение сессий и подключение вспомогательных функций и файла `db.php`.
2. Чтение и очистка данных формы (`title`, `category`, `ingredients`, `description`, массив `steps`).
3. Валидация полей; в случае ошибок данные и сообщения сохраняются в `$_SESSION` и происходит возврат на форму.

После успешной валидации формируется полное текстовое описание, объединяющее ингредиенты и описание:

```php
$fullDescription = "Ингредиенты:\n" . $ingredients . "\n\n" . $description;
```

Далее выполняется транзакция PDO с двумя запросами — в таблицу рецептов и в таблицу шагов:

```php
try {
    $pdo->beginTransaction();

    // Сохраняем основной рецепт
    $stmt = $pdo->prepare("
        INSERT INTO recipes (title, category, description)
        VALUES (:title, :category, :description)
    ");
    $stmt->execute([
        ':title'       => $title,
        ':category'    => $category,
        ':description' => $fullDescription,
    ]);

    $recipeId  = $pdo->lastInsertId();
    $stepsJson = json_encode($steps, JSON_UNESCAPED_UNICODE);

    // Сохраняем шаги приготовления
    $stmt2 = $pdo->prepare("
        INSERT INTO recipe_steps (recipe_id, steps_json)
        VALUES (:recipe_id, :steps_json)
    ");
    $stmt2->execute([
        ':recipe_id' => $recipeId,
        ':steps_json'=> $stepsJson,
    ]);

    $pdo->commit();

    $_SESSION['success'] = 'Рецепт успешно сохранён в Amazon RDS.';
    header('Location: ../index.php');
    exit();
} catch (PDOException $e) {
    $pdo->rollBack();
    $_SESSION['errors'] = [
        'db' => 'Ошибка сохранения в БД: ' . $e->getMessage(),
    ];
    $_SESSION['old'] = $_POST;
    header('Location: ../recipe/create.php');
    exit();
}
```

Если обработчик вызывается не POST-запросом, выполняется безопасный возврат на главную страницу.

Таким образом реализована операция **Create** для базы Amazon RDS.

#### 8. Реализация операций Read: вывод последних и всех рецептов

Главная страница `public/index.php` теперь читает данные не из файла `storage/recipes.txt`, а напрямую из таблицы `recipes` в Amazon RDS.
Выбираются два последних добавленных рецепта:

```php
<?php
/**
 * @file index.php
 * Главная страница каталога рецептов.
 * Теперь данные берутся из MySQL (Amazon RDS).
 */

require_once __DIR__ . '/../src/db.php';

$stmt = $pdo->query("
    SELECT id, title, category, description, created_at
    FROM recipes
    ORDER BY created_at DESC
    LIMIT 2
");
$latest = $stmt->fetchAll();
?>
```

![image](https://i.imgur.com/gAmcRLi.png)

Страница `public/recipe/index.php`, показывающая все рецепты, выполняет аналогичный запрос без ограничения `LIMIT`:

```php
require_once __DIR__ . '/../../src/db.php';

$stmt = $pdo->query("
    SELECT id, title, category, description, created_at
    FROM recipes
    ORDER BY created_at DESC
");
$recipes = $stmt->fetchAll();
```

Дальше в HTML-шаблонах эти массивы перебираются в цикле и выводятся на странице (название, категория, описание, дата добавления).
На страницах появляются ссылки «Редактировать» и «Удалить», которые ведут к соответствующим обработчикам и используют идентификатор рецепта.

#### 9. Реализация операций Update и Delete

Для завершения CRUD-функциональности необходимо добавить операции **Update** и **Delete**, работающие через базу Amazon RDS.

**9.1 Файл `edit.php` — форма редактирования рецепта**

Этот файл загружает текущие данные рецепта, шаги приготовления и выводит форму, уже заполненную старыми значениями.

```php
<?php
require_once __DIR__ . '/../src/db.php';

$id = $_GET['id'] ?? null;

if (!$id) {
    header('Location: index.php');
    exit;
}

try {
    // Получаем рецепт
    $stmt = $pdo->prepare("SELECT * FROM recipes WHERE id = :id");
    $stmt->execute([':id' => $id]);
    $recipe = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$recipe) {
        die("Рецепт не найден");
    }

    // Получаем шаги
    $stmt2 = $pdo->prepare("SELECT steps_json FROM recipe_steps WHERE recipe_id = :id");
    $stmt2->execute([':id' => $id]);
    $stepsRow = $stmt2->fetch();

    $steps = $stepsRow ? json_decode($stepsRow['steps_json'], true) : [];

} catch (PDOException $e) {
    die("Ошибка: " . $e->getMessage());
}
?>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Редактировать рецепт</title>
</head>
<body>

<h2>Редактировать рецепт</h2>

<form method="post" action="update_recipe.php">
    <input type="hidden" name="id" value="<?= htmlspecialchars($recipe['id']) ?>">

    <label>Название рецепта:</label><br>
    <input type="text" name="title" value="<?= htmlspecialchars($recipe['title']) ?>" required><br><br>

    <label>Категория:</label><br>
    <input type="text" name="category" value="<?= htmlspecialchars($recipe['category']) ?>" required><br><br>

    <label>Ингредиенты:</label><br>
    <textarea name="description" required><?= htmlspecialchars($recipe['description']) ?></textarea><br><br>

    <label>Шаги приготовления:</label><br>

    <div id="steps">
        <?php foreach ($steps as $s): ?>
            <input type="text" name="steps[]" value="<?= htmlspecialchars($s) ?>"><br>
        <?php endforeach; ?>
    </div>

    <button type="button" onclick="addStep()">Добавить шаг</button><br><br>

    <button type="submit">Сохранить изменения</button>
</form>

<script>
function addStep() {
    const block = document.getElementById('steps');
    const input = document.createElement('input');
    input.type = "text";
    input.name = "steps[]";
    block.appendChild(input);
    block.appendChild(document.createElement('br'));
}
</script>

</body>
</html>
```

**9.2 Файл `update_recipe.php` — обновление рецепта в RDS**

Файл принимает данные из формы `edit.php`, выполняет валидацию и обновляет данные в таблицах:

- `recipes`
- `recipe_steps`

Всё делается внутри транзакции.

```php
<?php
session_start();
require_once __DIR__ . '/../src/db.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: ../index.php');
    exit;
}

$id = $_POST['id'];
$title = trim($_POST['title']);
$category = trim($_POST['category']);
$description = trim($_POST['description']);
$steps = $_POST['steps'] ?? [];

if (!$title || !$category || !$description) {
    $_SESSION['errors'] = ['Заполните все поля.'];
    header("Location: edit.php?id=$id");
    exit;
}

try {
    $pdo->beginTransaction();

    // Обновление рецепта
    $stmt = $pdo->prepare("
        UPDATE recipes
        SET title = :title,
            category = :category,
            description = :description
        WHERE id = :id
    ");
    $stmt->execute([
        ':title' => $title,
        ':category' => $category,
        ':description' => $description,
        ':id' => $id
    ]);

    // Обновление шагов
    $steps = array_filter(array_map('trim', $steps));
    $stepsJson = json_encode($steps, JSON_UNESCAPED_UNICODE);

    $stmt = $pdo->prepare("
        UPDATE recipe_steps
        SET steps_json = :steps
        WHERE recipe_id = :id
    ");
    $stmt->execute([
        ':steps' => $stepsJson,
        ':id' => $id
    ]);

    $pdo->commit();
    $_SESSION['success'] = "Рецепт успешно обновлён.";
    header('Location: index.php');
    exit;

} catch (PDOException $e) {
    $pdo->rollBack();
    $_SESSION['errors'] = ["Ошибка обновления: " . $e->getMessage()];
    header("Location: edit.php?id=$id");
    exit;
}
```

**9.3 Файл `delete_recipe.php` — удаление рецепта**

Удаляет рецепт по ID:

- выполняется `DELETE FROM recipes`
- связанные шаги автоматически удаляются из `recipe_steps`, так как стоит `ON DELETE CASCADE`

```php
<?php
require_once __DIR__ . '/../src/db.php';

$id = $_GET['id'] ?? null;

if (!$id) {
    header('Location: index.php');
    exit;
}

try {
    $stmt = $pdo->prepare("DELETE FROM recipes WHERE id = :id");
    $stmt->execute([':id' => $id]);

    header('Location: index.php');
    exit;

} catch (PDOException $e) {
    die("Ошибка удаления: " . $e->getMessage());
}
```

#### 10. Проверка работы CRUD-операций через Amazon RDS

После развертывания приложение нужно открыть в браузере по публичному IP EC2:

```
http://3.127.69.157/index.php
```

1. После деплоя на EC2 главная страница отображала сообщение «Пока нет рецептов» и предлагала добавить новый рецепт.

![image](https://i.imgur.com/2UHBqDR.png)

2. Через форму добавления был создан рецепт «Быстрый овощной суп»: введены название, категория, ингредиенты, описание, выбран набор тегов и три шага приготовления.

![image](https://i.imgur.com/KouKy3Q.png)

3. После отправки формы данные успешно сохранились в Amazon RDS.
   Проверка через SQL-запросы показала, что запись появилась сразу в двух таблицах:

   ```sql
   SELECT * FROM recipes;
   SELECT * FROM recipe_steps;
   ```

![image](https://i.imgur.com/wufRYUs.png)

   В таблице `recipes` хранится основная информация (название, категория, объединённые ингредиенты и описание, дата добавления), а в `recipe_steps` — JSON-массив шагов приготовления, связанный по `recipe_id`.

4. На странице «Последние рецепты» отобразился только что добавленный рецепт, а на странице «Все рецепты» появились ссылки «Редактировать» и «Удалить» для выполнения операций Update и Delete. Операции **редактирования** и **удаления** были протестированы, что подтвердило корректную работу CRUD через Amazon RDS.

![image](https://i.imgur.com/IVgunxo.png)

В итоге приложение «Каталог рецептов» полностью перенесено с локального окружения на `Amazon RDS`: все данные хранятся в облачной базе, а операции **создания**, **чтения**, **обновления** и **удаления** выполняются через удалённый `MySQL-инстанс`. Доступ к приложению обеспечивается через EC2-инстанс с настроенным Apache и ограниченными inbound-правилами группы безопасности.

### Шаг 7. Дополнительное задание. Использование Amazon DynamoDB

#### 1. Создание таблицы в Amazon DynamoDB

Необходимо открыть сервис **DynamoDB** → **Tables** → **Create table**.

Заполнить параметры, как показано в таблице:

| Параметр      | Значение                |
| ------------- | ----------------------- |
| Table name    | `recipe_notes`          |
| Partition key | `recipe_id` (Number)    |
| Sort key      | `note_id` (String)      |
| Billing mode  | On-demand               |
| Encryption    | Default (AWS owned key) |

![image](https://i.imgur.com/A72GkoE.png)
![image](https://i.imgur.com/O6g678q.png)

#### 2. Добавление тестовых записей через AWS Console в таблицу

После создания таблицы нужно вручную добавить записи.

Необходимо перейти по пути **recipe_notes → Explore items → Create item**

**note-1:**

![image](https://i.imgur.com/9ZB34T5.png)

**note-2:**

![image](https://i.imgur.com/zusZziF.png)

После сохранения записей выполняется сканирование таблицы:

![image](https://i.imgur.com/ITXSiLV.png)

В таблице отображаются обе созданные записи.

>**Вопрос:**
>
>**Какие преимущества и недостатки использования DynamoDB по сравнению с реляционной базой данных Amazon RDS в вашем случае?**
>
>**Ответ:**
>
>- **Высокая скорость работы и масштабируемость** — операции чтения/записи по ключу выполняются очень быстро и автоматически масштабируются под нагрузку.
>- **Полностью управляемый сервис** — не нужно обновлять, настраивать или администрировать сервер БД.
>- **Подходит для частых мелких изменений** — заметки, комментарии, лайки и подобные структуры эффективно хранятся в DynamoDB.
>
>**Недостатки:**
>
>- **Нет SQL, JOIN и сложных запросов.**
  Нельзя легко объединить данные из разных сущностей, как это делается в RDS.
>- **Строгие требования к проектированию под конкретные запросы.**
  Сначала решаешь, как будешь читать данные — и только потом выбираешь ключи.
>- **Сложнее хранить связанные данные.**
  Для каждой сущности приходится создавать отдельные таблицы и дублировать информацию.

#### 3. Установка AWS SDK на EC2

Для работы с DynamoDB из PHP необходимо установить Composer и пакет `aws/aws-sdk-php`.

**Установка Composer:**

```bash
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php
composer --version
```

![image](https://i.imgur.com/iyARqoH.png)

**Установка AWS SDK:**

```bash
composer require aws/aws-sdk-php
```

![image](https://i.imgur.com/bLvLYn3.png)

#### 4. Подключение DynamoDB в приложении

В папке проекта нужно создать файл `src/dynamodb.php`

```php
<?php
// src/dynamodb.php
// Работа с таблицей recipe_notes в DynamoDB

require __DIR__ . '/../vendor/autoload.php';

use Aws\DynamoDb\DynamoDbClient;
use Aws\Exception\AwsException;

const DDB_TABLE = 'recipe_notes';

/**
 * Создаёт клиента DynamoDB.
 */
function getDynamoClient(): DynamoDbClient
{
    return new DynamoDbClient([
        'version' => 'latest',
        'region'  => 'eu-central-1', 
        'credentials' => [
            'key'    => 'YOUR_ACCESS_KEY_ID',
            'secret' => 'YOUR_SECRET_ACCESS_KEY',
        ],
    ]);
}

/**
 * Создание новой заметки для рецепта.
 *
 * @param int    $recipeId ID рецепта из RDS
 * @param string $text     Текст заметки
 * @return string|null     ID созданной заметки или null при ошибке / пустом тексте
 */
function createNote(int $recipeId, string $text): ?string
{
    $text = trim($text);
    if ($text === '') {
        return null;
    }

    $client = getDynamoClient();
    $noteId = 'note-' . time(); // простой уникальный ID

    try {
        $client->putItem([
            'TableName' => DDB_TABLE,
            'Item'      => [
                'recipe_id'  => ['N' => (string)$recipeId],
                'note_id'    => ['S' => $noteId],
                'text'       => ['S' => $text],
                'created_at' => ['S' => date('Y-m-d H:i:s')],
            ],
        ]);

        return $noteId;
    } catch (AwsException $e) {
        // Можно залогировать: error_log($e->getMessage());
        return null;
    }
}

/**
 * Получение всех заметок по рецепту.
 *
 * @param int $recipeId
 * @return array
 */
function getNotes(int $recipeId): array
{
    $client = getDynamoClient();

    try {
        $result = $client->query([
            'TableName' => DDB_TABLE,
            'KeyConditionExpression'     => 'recipe_id = :rid',
            'ExpressionAttributeValues'  => [
                ':rid' => ['N' => (string)$recipeId],
            ],
            // Если нужно отсортировать по note_id по возрастанию:
            'ScanIndexForward' => true,
        ]);

        $items = $result->get('Items') ?? [];
        $notes = [];

        foreach ($items as $item) {
            $notes[] = [
                'recipe_id'  => (int)($item['recipe_id']['N'] ?? 0),
                'note_id'    => $item['note_id']['S'] ?? '',
                'text'       => $item['text']['S'] ?? '',
                'created_at' => $item['created_at']['S'] ?? '',
            ];
        }

        return $notes;
    } catch (AwsException $e) {
        // error_log($e->getMessage());
        return [];
    }
}

/**
 * Обновление текста заметки.
 *
 * @param int    $recipeId
 * @param string $noteId
 * @param string $text
 * @return bool
 */
function updateNote(int $recipeId, string $noteId, string $text): bool
{
    $text = trim($text);
    if ($text === '') {
        return false;
    }

    $client = getDynamoClient();

    try {
        $client->updateItem([
            'TableName' => DDB_TABLE,
            'Key'       => [
                'recipe_id' => ['N' => (string)$recipeId],
                'note_id'   => ['S' => $noteId],
            ],
            'UpdateExpression'          => 'SET #t = :text',
            'ExpressionAttributeNames'  => [
                '#t' => 'text',
            ],
            'ExpressionAttributeValues' => [
                ':text' => ['S' => $text],
            ],
        ]);

        return true;
    } catch (AwsException $e) {
        // error_log($e->getMessage());
        return false;
    }
}

/**
 * Удаление заметки.
 *
 * @param int    $recipeId
 * @param string $noteId
 * @return bool
 */
function deleteNote(int $recipeId, string $noteId): bool
{
    $client = getDynamoClient();

    try {
        $client->deleteItem([
            'TableName' => DDB_TABLE,
            'Key'       => [
                'recipe_id' => ['N' => (string)$recipeId],
                'note_id'   => ['S' => $noteId],
            ],
        ]);

        return true;
    } catch (AwsException $e) {
        // error_log($e->getMessage());
        return false;
    }
}
```

Он содержит:

- Подключение AWS SDK
- Создание клиента DynamoDB
- CRUD-функции: `createNote()`, `updateNote()`, `deleteNote()`, `getNotes()`

#### 5. Интеграция в приложение (notes.php)

Файл `notes.php` нужно изменить для обработки форм:

- `create` — создаёт note в DynamoDB
- `update` — обновляет note
- `delete` — удаляет note
- GET — загружает список заметок для выбранного рецепта

```php
<?php
// public/recipe.php
require_once __DIR__ . '/../db.php';            // Подключение к MySQL (RDS)
require_once __DIR__ . '/../src/dynamodb.php'; // Функции работы с DynamoDB

// Получаем ID рецепта из GET, по умолчанию 1
$recipeId = isset($_GET['recipe_id']) ? (int)$_GET['recipe_id'] : 1;

// Обработка форм заметок (POST)
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    $text   = trim($_POST['text'] ?? '');
    $noteId = $_POST['note_id'] ?? '';

    try {
        switch ($action) {
            case 'create':
                if ($text !== '') {
                    createNote($recipeId, $text);
                }
                break;

            case 'update':
                if ($noteId !== '' && $text !== '') {
                    updateNote($recipeId, $noteId, $text);
                }
                break;

            case 'delete':
                if ($noteId !== '') {
                    deleteNote($recipeId, $noteId);
                }
                break;
        }
    } catch (Throwable $e) {
        // Можно вывести сообщение внизу страницы или залогировать
        // error_log($e->getMessage());
    }

    // После POST лучше сделать редирект, чтобы избежать повторной отправки формы
    header('Location: recipe.php?recipe_id=' . $recipeId);
    exit;
}

// Загрузка рецепта из RDS (MySQL)
$stmt = $pdo->prepare('SELECT * FROM recipes WHERE id = :id');
$stmt->execute(['id' => $recipeId]);
$recipe = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$recipe) {
    http_response_code(404);
    echo 'Рецепт не найден';
    exit;
}

// Загрузка заметок из DynamoDB
$notes = getNotes($recipeId);
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title><?= htmlspecialchars($recipe['title']) ?></title>
</head>
<body>
    <h1>Последние рецепты</h1>

    <h2><?= htmlspecialchars($recipe['title']) ?></h2>

    <p><strong>Категория:</strong>
        <?= htmlspecialchars($recipe['category'] ?? '') ?>
    </p>

    <p><strong>Ингредиенты:</strong><br>
        <?= nl2br(htmlspecialchars($recipe['ingredients'] ?? '')) ?>
    </p>

    <p><strong>Описание:</strong><br>
        <?= nl2br(htmlspecialchars($recipe['description'] ?? '')) ?>
    </p>

    <p><strong>Добавлен:</strong>
        <?= htmlspecialchars($recipe['created_at'] ?? '') ?>
    </p>

    <hr>

    <!-- Блок заметок из DynamoDB -->
    <h2>Заметки к рецепту (DynamoDB)</h2>

    <?php if (!empty($notes)): ?>
        <ul>
            <?php foreach ($notes as $note): ?>
                <li style="margin-bottom: 12px;">
                    <form method="post" style="margin-bottom: 4px;">
                        <textarea name="text" rows="2" cols="80"><?= htmlspecialchars($note['text']) ?></textarea><br>
                        <input type="hidden" name="note_id"   value="<?= htmlspecialchars($note['note_id']) ?>">
                        <button type="submit" name="action" value="update">Обновить</button>
                        <button type="submit" name="action" value="delete">Удалить</button>
                    </form>
                    <small>
                        ID: <?= htmlspecialchars($note['note_id']) ?>,
                        создана: <?= htmlspecialchars($note['created_at']) ?>
                    </small>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php else: ?>
        <p>Пока нет заметок.</p>
    <?php endif; ?>

    <h3>Добавить заметку</h3>
    <form method="post">
        <textarea name="text" rows="2" cols="80"></textarea><br>
        <button type="submit" name="action" value="create">Добавить</button>
    </form>

    <hr>

    <p><a href="/recipe/create.php">Добавить новый рецепт</a></p>
    <p><a href="/recipe/index.php">Все рецепты</a></p>
</body>
</html>
```

>**Вопрос:**
>
>**Какие сложности вы столкнулись при проектировании данных для DynamoDB по сравнению с реляционной моделью данных в Amazon RDS?**
>
>**Ответ:**
>
>- **Необходимо заранее продумать структуру запросов.**
  В отличие от SQL, где можно гибко фильтровать и объединять данные, DynamoDB требует заранее выбрать правильный Partition Key и Sort Key.
>- **Отсутствие связей между таблицами.**
  Нет FOREIGN KEY и нормальных JOIN, поэтому связанные данные (например, заметки и рецепт) нужно связывать вручную по идентификатору.
>- **Хранение данных в одной партиции.**
  Все заметки хранятся под одним ключом `recipe_id`, поэтому нужно следить за тем, чтобы партиции не становились слишком «тяжёлыми».
>- **Денормализация.**
  Иногда приходится дублировать данные, чтобы быстро получать нужные значения — это необычно после реляционной модели.

#### 6. Сценарий совместного использования RDS и DynamoDB

В одном приложении целесообразно использовать **обе** базы так:

- **Amazon RDS**:

  - Основное «ядро» данных: таблицы `users`, `recipes`, `categories`, `ingredients`.
  - Используется для:

    - регистрации/авторизации пользователей,
    - выборки списка рецептов по фильтрам (категория, сложность, время приготовления),
    - генерации отчётов и статистики.

- **Amazon DynamoDB**:

  - Хранит динамические и объёмные данные:

    - заметки к рецептам (`recipe_notes`),
    - потенциально лайки, комментарии, просмотры, историю изменений и др.
  - Используется там, где нужна:

    - высокая скорость записи и чтения,
    - гибкое масштабирование при росте нагрузки.

**Преимущества такого подхода:**

- Не перегружаем RDS большим количеством мелких операций (заметки/комментарии/лайки).
- Сохраняем удобство SQL и реляционной модели для основной логики.
- Получаем производительность и масштабируемость DynamoDB для «быстрых» данных.

### Шаг X. Дополнительное задание: автоматизация создания Security Group и EC2-инстанса с помощью Terraform

Для получения высшей оценки было выполнено дополнительное задание — автоматизация развёртывания виртуальной машины EC2 и Security Group с помощью инструмента **Terraform**. В данном шаге описан весь процесс: установка Terraform, подготовка конфигурации и создание ресурсов в AWS.

#### 1. Установка Terraform на EC2

Для начала необходимо установить Terraform на виртуальную машину:

```bash
sudo yum update -y
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform
terraform -version
```

После установки Terraform отобразил свою версию.

![image](https://i.imgur.com/MiTTm0i.png)
![image](https://i.imgur.com/t3w0i21.png)

#### 2. Создание рабочей директории Terraform

Далее необходимо подготовить отдельную директорию, где будут храниться конфигурации:

```bash
mkdir terraform-ec2
cd terraform-ec2
pwd
ls -la
```

![image](https://i.imgur.com/EXDUarE.png)

#### 3. Создание файлов `variables.tf` и `main.tf`

Для удобства конфигурация вынесена в два файла:

**Файл `variables.tf`** содержит параметры:

- регион AWS
- профиль CLI
- ID VPC
- ID подсети
- AMI
- тип EC2-инстанса
- имя SSH-ключа

```tf
# Регион AWS, где будут создаваться ресурсы
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1" # Frankfurt
}

# Профиль AWS CLI (чтобы не писать ключи в коде)
variable "aws_profile" {
  description = "AWS CLI profile name"
  type        = string
  default     = "default"
}

# ID VPC, в которой создаются ресурсы
variable "vpc_id" {
  description = "VPC ID where EC2 instance and Security Group will be created"
  type        = string
}

# ID подсети
variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

# AMI образ для EC2
variable "ami_id" {
  description = "AMI ID for EC2"
  type        = string
}

# Тип создаваемого EC2 инстанса
variable "instance_type" {
  description = "Тип EC2 инстанса"
  type        = string
}

# Имя SSH-ключа
variable "key_name" {
  description = "Имя SSH ключа"
  type        = string
}
```

**Файл `main.tf`** содержит ресурсы:

- Security Group с открытыми портами (SSH/HTTP)
- EC2-инстанс в выбранной подсети

```tf
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Security Group
resource "aws_security_group" "lab_sg" {
  name        = "lab-web-sg"
  description = "Security group for EC2 created via Terraform"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lab-web-sg"
  }
}

# EC2 instance
resource "aws_instance" "web_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.lab_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "lab-web-server"
  }
}
```

#### 4. Инициализация Terraform

Перед запуском конфигурации необходимо выполнить инициализацию:

```bash
terraform init
```

![image](https://i.imgur.com/zgPjMw2.png)

#### 5. Валидация конфигурации

Проверка корректности файлов:

```bash
terraform validate
```

![image](https://i.imgur.com/722tuhf.png)

#### 6. Настройка AWS CLI

Для работы Terraform использует учётные данные AWS:

```bash
aws configure
aws sts get-caller-identity
```

#### 6.1. Заполнение входных переменных Terraform

После настройки AWS CLI нужно передать Terraform значения переменных:

![image](https://i.imgur.com/AwQIcCB.png)

Здесь указываются:
- регион
- VPC
- подсеть
- AMI
- ключ
- тип EC2-инстанса

Эти параметры Terraform возьмёт для создания инфраструктуры.

#### 7. Просмотр плана развёртывания

Команда:

```bash
terraform plan
```

Показывает, какие ресурсы будут созданы:

- Security Group
- EC2 Instance

![image](https://i.imgur.com/m3WlN3Q.png)
![image](https://i.imgur.com/vzXVtAy.png)

#### 8. Создание ресурсов в AWS

Команда:

```bash
terraform apply
```

После запроса подтверждения необходимо ввести:

```
yes
```

Terraform создаёт виртуальную машину и отображает её ID.

![image](https://i.imgur.com/xleYCfV.png)
![image](https://i.imgur.com/TCpC9Vn.png)

Дополнительное условие выполнено:
**EC2-инстанс и Security Group были успешно развёрнуты средствами Terraform.**

## Вывод

**В ходе лабораторной работы была создана полноценная облачная инфраструктура на AWS:** настроены VPC, подсети, группы безопасности, развернут экземпляр MySQL в Amazon RDS и виртуальная машина EC2 для работы с базой данных.

Я подключился к базе, создал таблицы, выполнил CRUD-операции и проверил работу Read Replica, увидев механизм асинхронной репликации и ограничение режима *read-only*.

**Затем я подключил к RDS своё PHP-приложение «Каталог рецептов»**, перенёс всю работу с данными в облако и успешно реализовал операции создания, чтения, обновления и удаления через удалённый MySQL.

**Дополнительно была изучена NoSQL-модель:** создана таблица DynamoDB, добавлены записи и выполнена интеграция в приложение через AWS SDK.

**Завершающим этапом стала автоматизация развёртывания инфраструктуры через Terraform**, что позволило полностью автоматизировать создание Security Group и EC2-инстанса.

В итоге лабораторная работа дала цельное понимание различий и возможностей реляционных и нереляционных баз в AWS и практических навыков их применения в реальном веб-приложении.

## Библиография

1. [Amazon RDS Documentation](https://docs.aws.amazon.com/rds/index.html) — официальная документация по работе с **Amazon Relational Database Service**, созданию инстансов, настройке доступа и репликации.
2. [Amazon DynamoDB Documentation](https://docs.aws.amazon.com/dynamodb/index.html) — справочник по работе с NoSQL-хранилищем **DynamoDB**, проектированию таблиц и API-взаимодействию.
3. [AWS CLI Command Reference](https://docs.aws.amazon.com/cli/latest/index.html) — официальный справочник команд **AWS Command Line Interface**, использованных в работе.
4. [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) — руководство по ресурсу `aws_instance`, `aws_security_group` и настройке провайдера Terraform.
5. [MariaDB / MySQL Official Documentation](https://dev.mysql.com/doc/) — официальное руководство по SQL-командам, структуре таблиц и работе с реляционными БД.
