PB_USE_BUILTIN_MYSQL=0 \
PB_SYNC_TOKEN=changeme \
PB_MYSQL_DSN='root:mysql123@tcp(mysql:3306)/personal_butler?charset=utf8mb4&parseTime=True&loc=Local' \
./deploy.sh devbox --init