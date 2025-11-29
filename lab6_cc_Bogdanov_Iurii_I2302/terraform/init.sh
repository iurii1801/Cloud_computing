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
