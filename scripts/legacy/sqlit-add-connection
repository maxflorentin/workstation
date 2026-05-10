#!/usr/bin/env zsh
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Sqlit Connection Manager ===${NC}\n"

# Mostrar tipos de bases de datos disponibles
echo -e "${GREEN}Tipos de bases de datos disponibles:${NC}"
echo "1)  SQLite"
echo "2)  PostgreSQL"
echo "3)  MySQL"
echo "4)  MariaDB"
echo "5)  SQL Server (MSSQL)"
echo "6)  Oracle"
echo "7)  DuckDB"
echo "8)  ClickHouse"
echo "9)  CockroachDB"
echo "10) Snowflake"
echo "11) BigQuery"
echo "12) Redshift"
echo "13) Supabase"
echo "14) Turso"
echo "15) Custom URL (JDBC/otro)"
echo ""

read "db_type?Selecciona el tipo de base de datos (1-15): "

# Nombre de la conexión (común para todos)
read "conn_name?Nombre para esta conexión: "

case $db_type in
    1) # SQLite
        read "db_path?Ruta al archivo .db: "
        sqlit connections add sqlite --name "$conn_name" --path "$db_path"
        ;;
    
    2) # PostgreSQL
        read "server?Servidor (default: localhost): "
        server=${server:-localhost}
        read "port?Puerto (default: 5432): "
        port=${port:-5432}
        read "database?Nombre de la base de datos: "
        read "username?Usuario: "
        read -s "password?Contraseña: "
        echo ""
        
        sqlit connections add postgresql \
            --name "$conn_name" \
            --server "$server" \
            --port "$port" \
            --database "$database" \
            --username "$username" \
            --password "$password"
        ;;
    
    3|4) # MySQL / MariaDB
        provider="mysql"
        [[ $db_type == "4" ]] && provider="mariadb"
        
        read "server?Servidor (default: localhost): "
        server=${server:-localhost}
        read "port?Puerto (default: 3306): "
        port=${port:-3306}
        read "database?Nombre de la base de datos: "
        read "username?Usuario: "
        read -s "password?Contraseña: "
        echo ""
        
        sqlit connections add $provider \
            --name "$conn_name" \
            --server "$server" \
            --port "$port" \
            --database "$database" \
            --username "$username" \
            --password "$password"
        ;;
    
    5) # SQL Server (MSSQL)
        read "server?Servidor (default: localhost): "
        server=${server:-localhost}
        read "port?Puerto (default: 1433): "
        port=${port:-1433}
        read "database?Nombre de la base de datos: "
        
        echo "Tipo de autenticación:"
        echo "1) SQL Server Authentication"
        echo "2) Windows Authentication"
        read "auth_type?Selecciona (1-2): "
        
        if [[ $auth_type == "1" ]]; then
            read "username?Usuario: "
            read -s "password?Contraseña: "
            echo ""
            
            sqlit connections add mssql \
                --name "$conn_name" \
                --server "$server" \
                --port "$port" \
                --database "$database" \
                --auth-type sql \
                --username "$username" \
                --password "$password"
        else
            sqlit connections add mssql \
                --name "$conn_name" \
                --server "$server" \
                --port "$port" \
                --database "$database" \
                --auth-type windows
        fi
        ;;
    
    6) # Oracle
        read "server?Servidor (default: localhost): "
        server=${server:-localhost}
        read "port?Puerto (default: 1521): "
        port=${port:-1521}
        read "service_name?Service Name: "
        read "username?Usuario: "
        read -s "password?Contraseña: "
        echo ""
        
        sqlit connections add oracle \
            --name "$conn_name" \
            --server "$server" \
            --port "$port" \
            --service-name "$service_name" \
            --username "$username" \
            --password "$password"
        ;;
    
    7) # DuckDB
        read "db_path?Ruta al archivo .duckdb (o :memory: para en memoria): "
        sqlit connections add duckdb --name "$conn_name" --path "$db_path"
        ;;
    
    8) # ClickHouse
        read "server?Servidor (default: localhost): "
        server=${server:-localhost}
        read "port?Puerto (default: 8123): "
        port=${port:-8123}
        read "database?Nombre de la base de datos (default: default): "
        database=${database:-default}
        read "username?Usuario (default: default): "
        username=${username:-default}
        read -s "password?Contraseña: "
        echo ""
        
        sqlit connections add clickhouse \
            --name "$conn_name" \
            --server "$server" \
            --port "$port" \
            --database "$database" \
            --username "$username" \
            --password "$password"
        ;;
    
    9) # CockroachDB
        read "server?Servidor (default: localhost): "
        server=${server:-localhost}
        read "port?Puerto (default: 26257): "
        port=${port:-26257}
        read "database?Nombre de la base de datos: "
        read "username?Usuario: "
        read -s "password?Contraseña: "
        echo ""
        
        sqlit connections add cockroachdb \
            --name "$conn_name" \
            --server "$server" \
            --port "$port" \
            --database "$database" \
            --username "$username" \
            --password "$password"
        ;;
    
    10) # Snowflake
        read "account?Account identifier: "
        read "warehouse?Warehouse: "
        read "database?Database: "
        read "schema?Schema: "
        read "username?Usuario: "
        read -s "password?Contraseña: "
        echo ""
        
        sqlit connections add snowflake \
            --name "$conn_name" \
            --account "$account" \
            --warehouse "$warehouse" \
            --database "$database" \
            --schema "$schema" \
            --username "$username" \
            --password "$password"
        ;;
    
    11) # BigQuery
        read "project?Project ID: "
        read "dataset?Dataset: "
        read "credentials?Ruta al archivo de credenciales JSON: "
        
        sqlit connections add bigquery \
            --name "$conn_name" \
            --project "$project" \
            --dataset "$dataset" \
            --credentials "$credentials"
        ;;
    
    12) # Redshift
        read "server?Servidor: "
        read "port?Puerto (default: 5439): "
        port=${port:-5439}
        read "database?Nombre de la base de datos: "
        read "username?Usuario: "
        read -s "password?Contraseña: "
        echo ""
        
        sqlit connections add redshift \
            --name "$conn_name" \
            --server "$server" \
            --port "$port" \
            --database "$database" \
            --username "$username" \
            --password "$password"
        ;;
    
    13) # Supabase
        read "project_url?Project URL (e.g., https://xxx.supabase.co): "
        read "database?Database name (default: postgres): "
        database=${database:-postgres}
        read -s "password?Password: "
        echo ""
        
        sqlit connections add supabase \
            --name "$conn_name" \
            --url "$project_url" \
            --database "$database" \
            --password "$password"
        ;;
    
    14) # Turso
        read "database_url?Database URL: "
        read "auth_token?Auth token: "
        
        sqlit connections add turso \
            --name "$conn_name" \
            --url "$database_url" \
            --token "$auth_token"
        ;;
    
    15) # Custom URL
        echo -e "${YELLOW}Ejemplos de URLs:${NC}"
        echo "  PostgreSQL: postgresql://user:pass@host:5432/database"
        echo "  MySQL:      mysql://user:pass@host:3306/database"
        echo "  SQLite:     sqlite:///path/to/database.db"
        echo ""
        read "custom_url?URL de conexión completa: "
        
        sqlit connections add --url "$custom_url" --name "$conn_name"
        ;;
    
    *)
        echo -e "${RED}Opción no válida${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}✓ Conexión '$conn_name' agregada exitosamente${NC}"
echo -e "${BLUE}Usa 'sqlit connections list' para ver todas tus conexiones${NC}"
