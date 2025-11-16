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

