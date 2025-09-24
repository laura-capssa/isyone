# isyone

# Provisionamento Multi-Tenant do Odoo

## Visão Geral
Este repositório fornece um sistema de provisionamento automatizado para o Odoo 18 Community Edition em um ambiente multi-tenant. Ele utiliza o Docker Compose para orquestrar instâncias isoladas de Odoo e PostgreSQL para cada cliente, integrado com o Traefik para roteamento de proxy reverso via subdomínios (ex: `alfa.isy.one`). A configuração inclui monitoramento com Prometheus e Grafana para coleta e visualização de métricas.

A solução é projetada para ambientes prontos para produção:
- **Isolamento**: Cada cliente recebe uma instância dedicada de Odoo e um banco de dados PostgreSQL.
- **Automação**: Um script shell (`provision_client.sh`) gera configurações específicas do cliente, arquivos de ambiente e arquivos Docker Compose.
- **Segurança**: Senhas aleatórias são geradas para bancos de dados e acesso admin do Odoo.
- **Escalabilidade**: Genérico para qualquer nome de cliente, com volumes persistentes para dados.
- **Monitoramento**: O Prometheus coleta métricas do Odoo; o Grafana fornece painéis de visualização.

Baseado no GitHub do Odoo: [https://github.com/odoo/odoo](https://github.com/odoo/odoo)  
Guia de Implantação Básica: [https://medium.com/@skyops.io/deploy-odoo-18-on-aws-ec2-with-ubuntu-24-04-b74b42fcd814](https://medium.com/@skyops.io/deploy-odoo-18-on-aws-ec2-with-ubuntu-24-04-b74b42fcd814)

## Pré-requisitos
Antes de configurar, certifique-se de que o seguinte esteja disponível:
- **Docker & Docker Compose**: Instalados e em execução (versão 3.8+ para Compose).
  - Instalar Docker: [Documentação Oficial do Docker](https://docs.docker.com/engine/install/)
  - Instalar Docker Compose: [Documentação Oficial do Compose](https://docs.docker.com/compose/install/)
- **Traefik**: Já em execução no host, configurado para monitorar contêineres Docker via labels. Assume que o Traefik está exposto nas portas 80/443 e usa a rede externa `traefik`.
  - Arquivos de exemplo de configuração do Traefik estão em `/traefik/` (ex: `traefik.yml`, `docker-compose-traefik.yml`).
- **OpenSSL**: Para gerar senhas seguras (geralmente pré-instalado no Linux; instale via `apt install openssl` no Ubuntu).
- **Rede do Host**: 
  - A rede externa `traefik` deve existir (crie com `docker network create traefik` se necessário).
  - Resolução de domínio: Certifique-se de que subdomínios (ex: `*.isy.one`) apontem para o IP do seu servidor via DNS.
- **Portas**: 
  - 80/443 para Traefik (HTTP/HTTPS).
  - 8080 para o dashboard do Traefik (opcional).
  - 3000 para Grafana (interno; exponha via Traefik se necessário).
  - 9090 para Prometheus (interno).
- **SO**: Testado no Ubuntu 24.04; ajuste para outras distribuições.
- **Git**: Para clonar e gerenciar o repositório.

## Instruções de Configuração


2. **Configurar Ambiente Base**:
- Copie o arquivo `.env` base se necessário (contém configurações globais como o domínio base `isy.one`).
  ```
  cp .env.example .env  # Se um exemplo existir
  ```
- Edite `.env` para qualquer sobrescrita global (ex: domínio base).

3. **Configurar Traefik** (se não estiver em execução):
- Navegue para `/traefik/`:
  ```
  cd traefik
  docker-compose -f docker-compose-traefik.yml up -d
  ```
- Verifique: Acesse o dashboard do Traefik em `http://localhost:8080/dashboard/` (ou o IP do seu host).

4. **Configurar Monitoramento (Prometheus & Grafana)**:
- Navegue para `/monitoring/`:
  ```
  cd ../monitoring
  docker-compose -f docker-compose-monitoring.yml up -d
  ```
- Configure o Prometheus (`prometheus.yml` ou `/monitoring/prometheus.yml`) para coletar métricas dos endpoints do Odoo (ex: adicione jobs para `/metrics` do Odoo na porta 8069).
  - Exemplo de configuração de scrape em `prometheus.yml`:
    ```
    scrape_configs:
      - job_name: 'odoo'
        static_configs:
          - targets: ['odoo_alfa:8069']  # Adicione por cliente dinamicamente ou use descoberta de serviço
        metrics_path: /metrics
    ```
- Importe painéis do Grafana para métricas do Odoo (ex: via arquivos JSON em `/monitoring/`).
- Verifique:
  - Prometheus: `http://prometheus.isy.one/query` ou `http://localhost:9090`.
  - Grafana: `http://grafana.isy.one/login` (padrão: admin/admin).

5. **Criar Rede Externa** (se ausente): docker network create traefik

6. **Verificar Serviços Base**:

## Provisionamento de um Novo Cliente
Use o script de automação para criar um novo ambiente de cliente. O script gera:
- Um arquivo `.env.<cliente>` específico do cliente com credenciais.
- Um arquivo `docker-compose-<cliente>.yml` para os serviços Odoo e Postgres.
- Labels do Traefik para roteamento de subdomínio (ex: `alfa.isy.one`).

- Exemplo para "alfa":
  ```
  ./provision_client.sh alfa
  ```
- Saída:
  - Cria `.env.alfa` com variáveis como `POSTGRES_PASSWORD`, `ODOO_ADMIN_PASSWORD`.
  - Cria `docker-compose-alfa.yml` com serviços `postgres_alfa` e `odoo_alfa`.
  - Domínio: `alfa.isy.one`.
  - Pula se `docker-compose-<cliente>.yml` já existir.

2. **Iniciar os Serviços do Cliente**: docker-compose -f docker-compose-alfa.yml --env-file .env.alfa up -d

- Aguarde as verificações de saúde (Postgres pronto em ~1-2 min).
- Verifique:
  ```
  docker ps
  ```
  Adições esperadas:
  ```
  c76c3a351b4b   odoo:18.0                "/entrypoint.sh odoo"    11 minutes ago   Up 23 seconds   8069/tcp, 8071-8072/tcp                                                                                               odoo_alfa
  04c757b332e1   postgres:15              "docker-entrypoint.s…"   11 minutes ago   Up 11 minutes   5432/tcp                                                                                                              postgres_alfa
  ```

3. **Acessar a Instância do Odoo**:
- URL: `http://<cliente>.isy.one` (ex: `http://alfa.isy.one/`).
- Configuração Inicial: O Odoo solicitará a criação do banco de dados; use a `ADMIN_PASSWORD` gerada de `.env.<cliente>`.
- Roteamento do Traefik: Labels garantem que o tráfego para o subdomínio seja roteado para a porta 8069 do Odoo.

4. **Para Múltiplos Clientes**:
- Repita os passos para cada um (ex: `./provision_client.sh beta` → `beta.isy.one`).
- Todos compartilham a rede `traefik`, mas permanecem isolados via volumes (`pgdata_<cliente>`, `odoo_data_<cliente>`).

## Monitoramento e Métricas
- **Prometheus**: Coleta métricas do Odoo (ex: contagens de requisições, consultas de banco de dados).
- Consultar métricas: `http://prometheus.isy.one/query` ou `http://localhost:9090`.
- Certifique-se de que o Odoo exponha `/metrics` (habilitado por padrão no Odoo 18; adicione `--workers=0` se necessário para métricas single-threaded).
- Atualize `prometheus.yml` para incluir novos clientes dinamicamente (ex: via file_sd_configs para auto-descoberta).

- **Grafana**:
- Login: `http://grafana.isy.one/login` (admin/admin; altere a senha).
- Fonte de Dados: Adicione Prometheus como fonte (URL: `http://prometheus:9090`).
- Painéis: Importe painéis específicos do Odoo (ex: para CPU, memória, conexões de BD).
- Exemplos de Consultas:
 - Requisições do Odoo: `rate(odoo_http_requests_total[5m])`.
 - Conexões do Postgres: `pg_stat_database_connections`.

- **Alertas**: Configure em `/monitoring/alerts.yml` para o Prometheus (ex: alertas de alta CPU).

## Segurança e Melhores Práticas
- **Senhas**: Geradas automaticamente e armazenadas em `.env.<cliente>` (mantenha seguras; adicione ao `.gitignore`).
- **Volumes**: Armazenamento local persistente para dados do Postgres e filestore do Odoo.
- **HTTPS**: Configure o Traefik para SSL (adicione Let's Encrypt em `traefik.yml`).
- **Backups**: Faça backup de volumes manualmente (ex: `docker volume backup pgdata_alfa`).
- **Atualizações**: Puxe imagens mais recentes: `docker-compose pull`.
- **Escalabilidade**: Para produção, adicione réplicas ou use Docker Swarm/Kubernetes.

## Solução de Problemas
- **Traefik Não Roteando**:
- Verifique labels em `docker-compose-<cliente>.yml`.
- Verifique rede: `docker network inspect traefik`.
- Logs: `docker logs traefik`.
- **Problemas de Conexão do Odoo**:
- Saúde do Postgres: `docker logs postgres_<cliente>`.
- Vars de ambiente: Certifique-se de usar `--env-file`.
- **Monitoramento Não Coletando**:
- Adicione cliente à configuração do Prometheus e reinicie: `docker-compose -f docker-compose-monitoring.yml restart`.
- Métricas do Odoo: Confirme que o Odoo execute com `--longpolling-port=8072` se necessário.
- **Erros de Permissão**: Execute o script como non-root; corrija com `chmod +x provision_client.sh`.
- **DNS/Subdomínio**: Teste com `curl http://alfa.isy.one` ou edite `/etc/hosts` para testes locais.
- **Logs**: Geral: `docker logs <nome_container>` (ex: `docker logs odoo_alfa`).

## Explicação das Escolhas
- **Docker Compose**: Orquestração simples para apps multi-serviço; versão 3.8 para verificações de saúde.
- **Labels do Traefik**: Roteamento dinâmico sem exposição de portas; assume configuração externa do Traefik.
- **Automação do Script**: Bash para portabilidade; usa `cat << EOF` para templating; verifica duplicatas.
- **Isolamento**: Serviços/volumes por cliente previnem vazamento de dados em multi-tenant.
- **Odoo 18**: Versão estável mais recente; Community Edition para custo zero.
- **Postgres 15**: Compatível com Odoo; verificações de saúde garantem prontidão.

Para dúvidas ou contribuições, abra uma issue. Esta configuração é orientada para produção, mas teste em staging primeiro!

