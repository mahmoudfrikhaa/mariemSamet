# Simulation Autoware + AWSIM — raccourcis
# Usage : make <cible>   (make seul affiche l'aide)

SHELL := /bin/bash
S     := ./scripts

.DEFAULT_GOAL := help

.PHONY: help setup docker-native native-setup check test download awsim-dl map models models-all pull awsim autoware engage drive psim shell topics hz clean-cache

help: ## Affiche cette aide
	@echo ""
	@echo "  Simulation Autoware dans AWSIM — cibles disponibles"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Ordre (Ubuntu natif) : native-setup -> download -> check -> awsim (term.1) -> autoware (term.2)"
	@echo "  Ordre (WSL)          : setup -> docker-native -> download -> check -> awsim (term.1) -> autoware (term.2)"
	@echo ""

setup: ## 1. Installe les paquets et regle le systeme (sudo)
	@$(S)/10_setup_host.sh

docker-native: ## 2. (WSL uniquement) Installe un moteur Docker natif
	@$(S)/11_setup_docker_native.sh

native-setup: ## 1+2. (Ubuntu natif) Paquets, Docker, GPU, reseau DDS (sudo)
	@$(S)/12_setup_native_ubuntu.sh

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

drive: ## 7bis. Conduite autonome dans AWSIM sans clic (but calcule a ~200 m)
	@$(S)/60_drive_awsim.sh

psim: ## Plan B : conduite autonome dans RViz, sans AWSIM
	@$(S)/90_planning_simulator.sh

test: ## Test automatise : pose la voiture, donne un but, verifie qu'elle roule
	@$(S)/91_test_autonomous_drive.sh

shell: ## Ouvre un shell ROS 2 dans le conteneur Autoware
	@source $(S)/_common.sh && HOST_UID=$$(id -u) HOST_GID=$$(id -g) \
	  docker compose run --rm shell \
	  bash -c 'source /opt/autoware/setup.bash && exec bash'

topics: ## Liste les topics ROS 2 vus depuis le conteneur
	@source $(S)/_common.sh && HOST_UID=$$(id -u) HOST_GID=$$(id -g) \
	  docker compose run --rm shell \
	  bash -c 'source /opt/autoware/setup.bash && ros2 topic list'

hz: ## Mesure la frequence du LiDAR d'AWSIM
	@source $(S)/_common.sh && HOST_UID=$$(id -u) HOST_GID=$$(id -g) \
	  docker compose run --rm shell \
	  bash -c 'source /opt/autoware/setup.bash && ros2 topic hz /sensing/lidar/top/pointcloud_raw'

clean-cache: ## Supprime les archives telechargees (garde l'installation)
	@rm -rf $$HOME/Downloads/awsim && echo "Cache supprime."
