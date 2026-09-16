# Simulation Autoware + AWSIM — raccourcis
# Usage : make <cible>   (make seul affiche l'aide)

SHELL := /bin/bash
S     := ./scripts

.DEFAULT_GOAL := help

.PHONY: help setup docker-native check test download awsim-dl map models models-all pull awsim autoware engage psim shell topics hz clean-cache

help: ## Affiche cette aide
	@echo ""
	@echo "  Simulation Autoware dans AWSIM — cibles disponibles"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Ordre : setup -> docker-native -> download -> check -> awsim (term.1) -> autoware (term.2)"
	@echo ""

setup: ## 1. Installe les paquets et regle le systeme (sudo)
	@$(S)/10_setup_host.sh

docker-native: ## 2. Installe un moteur Docker natif (obligatoire : voir README)
	@$(S)/11_setup_docker_native.sh

download: awsim-dl map models pull ## 3. Telecharge tout (~35 Go)

awsim-dl: ## Telecharge le simulateur AWSIM
	@$(S)/20_download_awsim.sh

map: ## Telecharge la carte Nishi-Shinjuku
	@$(S)/21_download_map.sh

models: ## Telecharge les modeles de perception
	@$(S)/22_download_models.sh

models-all: ## Telecharge TOUS les modeles (tres volumineux)
	@$(S)/22_download_models.sh --all

pull: ## Telecharge l'image Docker Autoware
	@source $(S)/_common.sh && docker pull $$AUTOWARE_IMAGE

check: ## 4. Diagnostic complet de la machine
	@$(S)/00_check_env.sh

awsim: ## 5. Lance AWSIM (terminal 1)
	@$(S)/30_run_awsim.sh

autoware: ## 6. Lance Autoware (terminal 2)
	@$(S)/40_run_autoware.sh

engage: ## 7. Demarre la conduite autonome (terminal 3)
	@$(S)/50_engage.sh

psim: ## Plan B : conduite autonome dans RViz, sans AWSIM
	@$(S)/90_planning_simulator.sh

test: ## Test automatise : pose la voiture, donne un but, verifie qu'elle roule
	@$(S)/91_test_autonomous_drive.sh

shell: ## Ouvre un shell ROS 2 dans le conteneur Autoware
	@cd docker && HOST_UID=$$(id -u) HOST_GID=$$(id -g) \
	  docker compose -f awsim.compose.yaml run --rm shell \
	  bash -c 'source /opt/autoware/setup.bash && exec bash'

topics: ## Liste les topics ROS 2 vus depuis le conteneur
	@cd docker && HOST_UID=$$(id -u) HOST_GID=$$(id -g) \
	  docker compose -f awsim.compose.yaml run --rm shell \
	  bash -c 'source /opt/autoware/setup.bash && ros2 topic list'

hz: ## Mesure la frequence du LiDAR d'AWSIM
	@cd docker && HOST_UID=$$(id -u) HOST_GID=$$(id -g) \
	  docker compose -f awsim.compose.yaml run --rm shell \
	  bash -c 'source /opt/autoware/setup.bash && ros2 topic hz /sensing/lidar/top/pointcloud_raw'

clean-cache: ## Supprime les archives telechargees (garde l'installation)
	@rm -rf $$HOME/Downloads/awsim && echo "Cache supprime."
