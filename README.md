# isyone

# Provisionamento Multi-Tenant do Odoo

## Visão Geral
Este repositório fornece um sistema de provisionamento automatizado para o Odoo 18 Community Edition em um ambiente multi-tenant. Ele utiliza o Docker Compose para orquestrar instâncias isoladas de Odoo e PostgreSQL para cada cliente, integrado com o Traefik para roteamento de proxy reverso via subdomínios (ex: `alfa.isy.one`). A configuração inclui monitoramento com Prometheus e Grafana para coleta e visualização de métricas, além de suporte a alertas e auto-descoberta de serviços.

A solução é projetada para ambientes prontos para produção:
- **Isolamento**: Cada cliente recebe uma instância dedicada de Odoo e um banco de dados PostgreSQL, com volumes persistentes para evitar vazamentos de dados.
- **Automação**: Um script shell (`provision_client.sh`) gera configurações específicas do cliente, arquivos de ambiente e arquivos Docker Compose, incluindo verificações de duplicatas e geração de senhas seguras.
- **Segurança**: Senhas aleatórias são geradas para bancos de dados e acesso admin do Odoo, com suporte a HTTPS via Traefik e Let's Encrypt.
- **Escalabilidade**: Genérico para qualquer nome de cliente, com suporte a réplicas e integração com orquestradores como Docker Swarm ou Kubernetes para expansão horizontal.
- **Monitoramento**: O Prometheus coleta métricas do Odoo e PostgreSQL; o Grafana fornece painéis de visualização personalizáveis, com alertas configuráveis para downtime ou sobrecarga.

Baseado no GitHub do Odoo: [https://github.com/odoo/odoo](https://github.com/odoo/odoo)  
Guia de Implantação Básica: [https://medium.com/@skyops.io/deploy-odoo-18-on-aws-ec2-with-ubuntu-24-04-b74b42fcd814](https://medium.com/@skyops.io/deploy-odoo-18-on-aws-ec2-with-ubuntu-24-04-b74b42fcd814)  
Documentação do Traefik: [https://doc.traefik.io/traefik/](https://doc.traefik.io/traefik/)

## Pré-requisitos
Antes de configurar, certifique-se de que o seguinte esteja disponível:
- **Docker & Docker Compose**: Instalados e em execução (versão 3.8+ para Compose, recomendada 4.x para recursos avançados como perfis).
  - Instalar Docker: [Documentação Oficial do Docker](https://docs.docker.com/engine/install/)
  - Instalar Docker Compose: [Documentação Oficial do Compose](https://docs.docker.com/compose/install/)
- **Traefik**: Já em execução no host, configurado para monitorar contêineres Docker via labels. Assume que o Traefik está exposto nas portas 80/443 e usa a rede externa `traefik`.
  - Arquivos de exemplo de configuração do Traefik estão em `/traefik/` (ex: `traefik.yml`, `docker-compose-traefik.yml`).
  - Para HTTPS, configure o provedor ACME (ex: Let's Encrypt) no `traefik.yml`.
- **OpenSSL**: Para gerar senhas seguras (geralmente pré-instalado no Linux; instale via `apt install openssl` no Ubuntu).
- **Rede do Host**: 
  - A rede externa `traefik` deve existir (crie com `docker network create traefik` se necessário).
  - Resolução de domínio: Certifique-se de que subdomínios (ex: `*.isy.one`) apontem para o IP do seu servidor via DNS (use ferramentas como Cloudflare ou Route 53 para wildcard DNS).
- **Portas**: 
  - 80/443 para Traefik (HTTP/HTTPS).
  - 8080 para o dashboard do Traefik (opcional; proteja com autenticação básica).
  - 3000 para Grafana (interno; exponha via Traefik se necessário, com autenticação).
  - 9090 para Prometheus (interno).
  - 8069 para Odoo (interno, roteado via Traefik).
- **SO**: Testado no Ubuntu 24.04; ajuste para outras distribuições (ex: CentOS com `yum install docker`).
- **Git**: Para clonar e gerenciar o repositório.
- **Recursos do Servidor**: Mínimo 4GB RAM, 2 vCPUs por instância de cliente; monitore uso com `htop` ou `docker stats`.
- **Ferramentas Adicionais**: `jq` para parsing JSON em scripts (instale via `apt install jq` se necessário para extensões de automação).

## Instruções de Configuração

1. **Clonar o Repositório**:
   - Clone o repositório para o seu servidor:
     ```
     git clone https://github.com/laura-capssa/isyone/  
     cd isyone
     ```
   - Verifique dependências: `docker --version`, `docker compose version`, `openssl version`.

2. **Configurar Ambiente Base**:
   - Copie o arquivo `.env` base se necessário (contém configurações globais como o domínio base `isy.one`).
     ```
     cp .env
     ```
   - Edite `.env` para qualquer sobrescrita global (ex: domínio base, timezone, ou limites de recursos como `ODOO_WORKERS=2`).
   - Adicione `.env*` ao `.gitignore` para evitar commit de credenciais.

3. **Configurar Traefik** (se não estiver em execução):
   - Navegue para `/traefik/`:
     ```
     cd traefik
     docker-compose -f docker-compose-traefik.yml up -d
     ```
   - Verifique: Acesse o dashboard do Traefik em `http://localhost:8080/dashboard/` (ou o IP do seu host). Ative o dashboard no `traefik.yml` com `api.dashboard: true`.
   - Para HTTPS: Adicione certificados no `traefik.yml` e reinicie.

4. **Configurar Monitoramento (Prometheus & Grafana)**:
   - Navegue para `/monitoring/`:
     ```
     cd ../monitoring
     docker-compose -f docker-compose-monitoring.yml up -d
     ```
   - Configure o Prometheus (`prometheus.yml` ou `/monitoring/prometheus.yml`) para coletar métricas dos endpoints do Odoo (ex: adicione jobs para `/metrics` do Odoo na porta 8069). Para auto-descoberta, use `docker_sd_configs` para escanear contêineres rotulados.
     - Exemplo de configuração de scrape em `prometheus.yml`:
       ```
       scrape_configs:
         - job_name: 'odoo'
           docker_sd_configs:
             - host: unix:///var/run/docker.sock
               port: 8069
               relabel_configs:
                 - source_labels: [__meta_docker_container_name]
                   regex: 'odoo_(.+)'
                   target_label: instance
           metrics_path: /metrics
         - job_name: 'postgres'
           static_configs:
             - targets: ['postgres_alfa:9187']  # Use exporter do Postgres para métricas
       ```
   - Importe painéis do Grafana para métricas do Odoo (ex: via arquivos JSON em `/monitoring/dashboards/` ou ID 1860 do Grafana Labs para Odoo genérico).
   - Verifique:
     - Prometheus: `http://prometheus.isy.one/query` ou `http://localhost:9090`. Para confirmar métricas do Odoo, acesse diretamente o endpoint interno como `http://172.24.0.6:8069/metrics` (substitua pelo IP do contêiner via `docker inspect odoo_alfa | grep IPAddress` – isso é para depuração interna; use Prometheus para produção).
     - Grafana: `http://grafana.isy.one/login` (padrão: admin/admin; altere imediatamente via UI).

5. **Criar Rede Externa** (se ausente):
   ```
   docker network create traefik
   ```

6. **Verificar Serviços Base**:
   ```
   docker ps | grep -E "(traefik|prometheus|grafana)"
   ```
   - Todos os serviços base devem estar "Up". Se não, verifique logs com `docker logs <container>`.

## Provisionamento de um Novo Cliente
Use o script de automação para criar um novo ambiente de cliente. O script gera:
- Um arquivo `.env.<cliente>` específico do cliente com credenciais (ex: senhas geradas via `openssl rand -base64 32`).
- Um arquivo `docker-compose-<cliente>.yml` para os serviços Odoo e Postgres, com healthchecks e labels do Traefik.
- Labels do Traefik para roteamento de subdomínio (ex: `alfa.isy.one`), incluindo middlewares para compressão e rate-limiting.

- Exemplo para "alfa":
  ```
  ./provision_client.sh alfa
  ```
- Saída:
  - Cria `.env.alfa` com variáveis como `POSTGRES_PASSWORD`, `ODOO_ADMIN_PASSWORD`, `ODOO_DB_HOST=postgres_alfa`.
  - Cria `docker-compose-alfa.yml` com serviços `postgres_alfa` e `odoo_alfa`, volumes `pgdata_alfa` e `odoo_data_alfa`.
  - Domínio: `alfa.isy.one`.
  - Pula se `docker-compose-<cliente>.yml` já existir; use `./provision_client.sh --force alfa` para recriar.

2. **Iniciar os Serviços do Cliente**:
   ```
   docker-compose -f docker-compose-alfa.yml --env-file .env.alfa up -d
   ```
   - Aguarde as verificações de saúde (Postgres pronto em ~1-2 min; Odoo inicia após DB pronto).
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
   - URL: `http://<cliente>.isy.one` (ex: `http://alfa.isy.one/`; redireciona para HTTPS se configurado).
   - Configuração Inicial: O Odoo solicitará a criação do banco de dados; use a `ADMIN_PASSWORD` gerada de `.env.<cliente>`.
   - Roteamento do Traefik: Labels garantem que o tráfego para o subdomínio seja roteado para a porta 8069 do Odoo. Para depuração, teste com `curl -H "Host: alfa.isy.one" http://localhost`.

4. **Para Múltiplos Clientes**:
   - Repita os passos para cada um (ex: `./provision_client.sh beta` → `beta.isy.one`).
   - Todos compartilham a rede `traefik`, mas permanecem isolados via volumes (`pgdata_<cliente>`, `odoo_data_<cliente>`) e namespaces de contêineres.
   - Limite: Monitore recursos totais; use `docker stats` para alocação por cliente.

## Monitoramento e Métricas
O monitoramento é centralizado para fornecer visibilidade em tempo real sobre performance, uso de recursos e saúde dos serviços. Ele cobre métricas do Odoo (requisições HTTP, consultas SQL, longpolling) e PostgreSQL (conexões, locks, I/O).

- **Prometheus**: Coleta métricas do Odoo e Postgres via exporters. O Odoo 18 expõe métricas Prometheus por padrão no endpoint `/metrics` (habilitado com `--dev=all` ou em produção com workers configurados).
  - Configuração: Edite `prometheus.yml` para incluir jobs dinâmicos. Para novos clientes, adicione alvos manualmente ou use auto-descoberta via Docker labels (ex: `prometheus_io_scrape: "true"` nos docker-compose do cliente).
  - Confirmar Métricas: Após iniciar um cliente (ex: alfa), acesse o endpoint interno do Odoo para validar: `http://172.24.0.6:8069/metrics` (substitua `172.24.0.6` pelo IP real do contêiner via `docker inspect odoo_alfa | grep IPAddress`). Isso deve retornar métricas como `odoo_http_requests_total{code="200"}`. Em produção, use o Prometheus para query: `http://prometheus.isy.one/query?query=up{job="odoo"}`.
  - Exporters Adicionais: Inclua o Postgres Exporter (`postgres_exporter:15`) no docker-compose do cliente para métricas de BD (porta 9187).
  - Atualizações: Reinicie Prometheus após adicionar clientes: `docker-compose -f docker-compose-monitoring.yml restart prometheus`.

- **Grafana**:
  - Login: `http://grafana.isy.one/login` (admin/admin; altere a senha via UI e configure autenticação LDAP/OAuth para produção).
  - Fonte de Dados: Adicione Prometheus como fonte (URL: `http://prometheus:9090` dentro da rede Docker).
  - Painéis: Importe painéis específicos do Odoo (ex: dashboard ID 1860 do Grafana Labs para Odoo, ou JSON customizados em `/monitoring/dashboards/odoo-dashboard.json`). Crie painéis para:
    - Uso de CPU/Memória por contêiner: `container_cpu_usage_seconds_total{container=~"odoo_.*"}`.
    - Requisições do Odoo: `rate(odoo_http_requests_total[5m])` com filtros por cliente.
    - Conexões do Postgres: `pg_stat_database_connections{datname="odoo_alfa"}`.
    - Latência de Queries: `histogram_quantile(0.95, rate(odoo_sql_query_duration_seconds_bucket[5m]))`.
  - Variáveis: Use variáveis de dashboard para selecionar clientes (ex: `$cliente` em queries como `up{instance=~"$cliente:8069"}`).

- **Alertas**: Configure em `/monitoring/alerts.yml` para o Prometheus (ex: alertas de alta CPU >80% por 5min, ou downtime do Odoo). Integre com ferramentas como Alertmanager para notificações via Slack/Email.
  - Exemplo de Regra:
    ```
    groups:
    - name: odoo_alerts
      rules:
      - alert: OdooHighCPU
        expr: rate(container_cpu_usage_seconds_total{container=~"odoo_.*"}[5m]) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Alta CPU no Odoo {{ $labels.container }}"
    ```
  - Reinicie Alertmanager: `docker-compose -f docker-compose-monitoring.yml restart alertmanager`.

- **Logs e Tracing**: Para logs centralizados, adicione ELK Stack (Elasticsearch, Logstash, Kibana) em uma extensão futura. Use `docker logs -f odoo_alfa` para depuração imediata.

### Verificação de Funcionamento para o Cliente Alfa

Após provisionar e iniciar os serviços do cliente "alfa", você pode validar o funcionamento completo acessando os seguintes endpoints para comprovar que o sistema está rodando corretamente. Esses links confirmam o roteamento do Traefik, a coleta de métricas no Prometheus, a visualização no Grafana e o acesso ao Odoo, além da exposição de métricas internas para depuração:

- **Dashboard do Traefik**: Acesse `http://localhost:8080/dashboard/` para visualizar o roteador e serviço do Odoo alfa (procure por "odoo-alfa" na lista de routers; deve mostrar status "healthy" e tráfego roteado para `alfa.isy.one`).
- **Consulta no Prometheus**: Vá para `http://prometheus.isy.one/query` e execute uma query como `up{job="odoo"}` ou `odoo_http_requests_total` para confirmar que métricas do Odoo alfa estão sendo coletadas (deve retornar valores >0 para o alvo `odoo_alfa:8069`).
- **Login no Grafana**: Acesse `http://grafana.isy.one/login` (use credenciais admin/admin), selecione o dashboard do Odoo e verifique painéis com dados em tempo real para o cliente alfa, como taxa de requisições ou uso de CPU (ex: filtre por `instance=~"odoo_alfa"`).
- **Interface do Odoo**: Navegue para `http://alfa.isy.one/odoo/apps` (após login inicial com a senha admin gerada); isso deve carregar a página de aplicativos do Odoo, confirmando que o roteamento via Traefik está funcional e o banco de dados está conectado.
- **Métricas Internas do Odoo (para depuração)**: Para validar o endpoint de métricas diretamente, acesse `http://172.24.0.6:8069/metrics` (substitua `172.24.0.6` pelo IP real do contêiner `odoo_alfa` obtido via `docker inspect odoo_alfa | grep IPAddress`); deve retornar uma página com métricas Prometheus como `odoo_http_requests_total` e `odoo_database_size`, indicando que o Odoo está expondo dados corretamente (use isso apenas em rede interna, não exponha publicamente).

Se algum link falhar, verifique logs dos contêineres relevantes (`docker logs odoo_alfa` ou `docker logs traefik`) e certifique-se de que o DNS para `*.isy.one` está resolvendo corretamente.


## Segurança e Melhores Práticas
- **Senhas**: Geradas automaticamente e armazenadas em `.env.<cliente>` (mantenha seguras; adicione ao `.gitignore`). Use gerenciadores como Vault para produção.
- **Volumes**: Armazenamento local persistente para dados do Postgres e filestore do Odoo. Faça backup regular com `docker volume ls` e ferramentas como `duplicity` ou AWS S3.
- **HTTPS**: Configure o Traefik para SSL automático com Let's Encrypt (adicione no `traefik.yml`: `certificatesResolvers.myresolver.acme.email=seu@email.com`).
- **Backups**: Automatize com cron jobs: `docker run --rm -v pgdata_alfa:/data busybox tar czf /backup/pgdata_alfa.tar.gz /data`. Armazene off-site.
- **Atualizações**: Puxe imagens mais recentes: `docker-compose pull && docker-compose up -d`. Teste em staging antes de produção.
- **Escalabilidade**: Para >10 clientes, migre para Docker Swarm (`docker swarm init`) ou Kubernetes com Helm charts para Odoo. Monitore com `docker stats` ou cAdvisor.
- **Auditoria**: Ative logs de auditoria no Odoo (`--log-level=info`) e integre com SIEM tools.
- **Compliance**: Para GDPR/HIPAA, adicione criptografia em repouso nos volumes (use LUKS no host).

## Solução de Problemas
- **Traefik Não Roteando**:
  - Verifique labels em `docker-compose-<cliente>.yml` (ex: `traefik.http.routers.odoo-alfa.rule=Host(\`alfa.isy.one\`)`).
  - Verifique rede: `docker network inspect traefik` (contêineres devem estar conectados).
  - Logs: `docker logs traefik`. Teste: `curl -H "Host: alfa.isy.one" http://localhost`.
- **Problemas de Conexão do Odoo**:
  - Saúde do Postgres: `docker logs postgres_<cliente>` (procure por "database system is ready").
  - Vars de ambiente: Certifique-se de usar `--env-file .env.<cliente>`. Verifique `ODOO_DB_PASSWORD`.
  - Erro de Migração: Reinicie Odoo após DB pronto: `docker-compose restart odoo_<cliente>`.
- **Monitoramento Não Coletando**:
  - Adicione cliente à configuração do Prometheus e reinicie: `docker-compose -f docker-compose-monitoring.yml restart`.
  - Métricas do Odoo: Confirme que o Odoo execute com `--longpolling-port=8072` e acesse `http://<IP_CONTAINER>:8069/metrics` para validar (ex: `http://172.24.0.6:8069/metrics`). Se vazio, adicione `--workers=0` para modo single-threaded.
  - Rede Interna: Certifique-se de que Prometheus acesse contêineres via rede `traefik` (use `host.docker.internal` se necessário).
- **Erros de Permissão**: Execute o script como non-root; corrija com `chmod +x provision_client.sh` e `chown -R $USER:$USER .`.
- **DNS/Subdomínio**: Teste com `curl http://alfa.isy.one` ou edite `/etc/hosts` para testes locais (ex: `127.0.0.1 alfa.isy.one`).
- **Logs**: Geral: `docker logs <nome_container>` `
