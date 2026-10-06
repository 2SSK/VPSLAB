N ?= 01

.PHONY: help up check ssh console ps logs stop start down reset

help:
	@echo 'make up              build and start vps-01..03, trust host keys, check'
	@echo 'make check           assert every node over SSH'
	@echo 'make ssh [N=01]      ssh deploy@vps-N'
	@echo 'make console [N=01]  root shell via docker exec'
	@echo 'make ps | logs       fleet status | logs of vps-N'
	@echo 'make stop | start    power off | power on, state kept'
	@echo 'make down            remove the nodes, keep the login key'
	@echo 'make reset           down, then up with fresh nodes'

up:
	@scripts/lab.sh keys
	docker compose up -d --build --wait
	@scripts/lab.sh trust
	@scripts/lab.sh check

check:
	@scripts/lab.sh check

ssh:
	@ssh -F keys/ssh_config vps-$(N)

console:
	@docker exec -it vps-$(N) bash

ps:
	@docker compose ps

logs:
	@docker exec vps-$(N) journalctl -n 100 --no-pager

stop:
	docker compose stop

start:
	docker compose up -d --wait --no-build
	@scripts/lab.sh check

down:
	docker compose down
	@rm -f keys/known_hosts keys/ssh_config

reset: down up
