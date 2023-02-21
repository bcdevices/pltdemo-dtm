#
# Copyright (c) 2019-2022 Blue Clover Devices
#
# SPDX-License-Identifier: Apache-2.0
#

PRJTAG := pltdemo-dtm

# Makefile default shell is /bin/sh which does not implement `source`.
SHELL := /bin/bash

BASE_PATH := $(realpath .)
DIST := $(BASE_PATH)/dist

.PHONY: default
default: build

.PHONY: GIT-VERSION-FILE
GIT-VERSION-FILE:
	@sh ./GIT-VERSION-GEN
-include GIT-VERSION-FILE

VERSION_TAG := $(patsubst v%,%,$(GIT_DESC))

DOCKER_BUILD_ARGS :=
DOCKER_BUILD_ARGS += --network=host

DOCKER_RUN_ARGS :=
DOCKER_RUN_ARGS += --network=none

ZEPHYR_TAG := 3.0.0
ZEPHYR_SYSROOT := /usr/src/zephyr-$(ZEPHYR_TAG)/zephyr
ZEPHYR_USRROOT := $(HOME)/src/zephyr-$(ZEPHYR_TAG)/zephyr

BOARDS_APP :=
BOARDS_APP += blueclover_plt_demo_v2_nrf52832

SHELL_TARGETS := $(patsubst %,build.%/shell/zephyr/zephyr.hex,$(BOARDS_APP))
TESTER_TARGETS := $(patsubst %,build.%/tester/zephyr/zephyr.hex,$(BOARDS_APP))

build.%/tester/zephyr/zephyr.hex:
	if [ -d $(ZEPHYR_USRROOT) ]; then source $(ZEPHYR_USRROOT)/zephyr-env.sh ; \
	elif [ -d $(ZEPHYR_SYSROOT) ]; then source $(ZEPHYR_SYSROOT)/zephyr-env.sh ; \
	else echo "No Zephyr"; fi && \
          west build --build-dir build.$*/tester --pristine auto \
	  --board $*  $$ZEPHYR_BASE/tests/bluetooth/tester

build.%/shell/zephyr/zephyr.hex:
	if [ -d $(ZEPHYR_USRROOT) ]; then source $(ZEPHYR_USRROOT)/zephyr-env.sh ; \
	elif [ -d $(ZEPHYR_SYSROOT) ]; then source $(ZEPHYR_SYSROOT)/zephyr-env.sh ; \
	else echo "No Zephyr"; fi && \
          west build --build-dir build.$*/shell --pristine auto \
	  --board $*  $$ZEPHYR_BASE/samples/subsys/shell/shell_module \
	-DCONFIG_GPIO_SHELL=y \
	-DCONFIG_SENSOR=y \
	-DCONFIG_SHT3XD=y \
	-DCONFIG_TEMP_NRF5=y \
	-DCONFIG_I2C=y \
	-DCONFIG_BT=y \
	-DCONFIG_BT_PERIPHERAL=y \
	-DCONFIG_BT_DIS=y \
	-DCONFIG_BT_DIS_PNP=n \
	-DCONFIG_BT_CTLR_DTM_HCI=y \
	-DCONFIG_BT_SHELL=y

.PHONY: versions
versions:
	@echo "GIT_DESC: $(GIT_DESC)"
	@echo "VERSION_TAG: $(VERSION_TAG)"

.PHONY: build
build: $(SHELL_TARGETS) $(TESTER_TARGETS)

.PHONY: clean
clean:
	-rm -rf $(BINS) build build.*

.PHONY: prereq
prereq:
	pip3 install -r requirements.txt
	install -d zephyrproject
	cd zephyrproject && west init --mr v$(ZEPHYR_TAG)
	cd zephyrproject && west update
	pip3 install -r $(ZEPHYR_USRROOT)/scripts/requirements.txt

.PHONY: dist-prep
dist-prep:
	-install -d $(DIST)

.PHONY: dist-clean
dist-clean:
	-rm -rf $(DIST)

.PHONY: dist
dist: dist-clean dist-prep build
	install -m 666 build.blueclover_plt_demo_v2_nrf52832/shell/zephyr/zephyr.hex dist/shell-pltdemov2-$(VERSION_TAG).hex
	install -m 666 build.blueclover_plt_demo_v2_nrf52832/tester/zephyr/zephyr.hex dist/tester-pltdemov2-$(VERSION_TAG).hex
	sed 's/{{BOARD}}/pltdemov2/g; s/{{VERSION}}/$(VERSION_TAG)/g' test-suites/ict-dtm.yaml.template > dist/ict-dtm-pltdemov2-$(VERSION_TAG).yaml

.PHONY: deploy
deploy:
	pltcloud -t "$(API_TOKEN)" -f "dist/*" -v "v$(VERSION_TAG)" -p "$(PROJECT_UUID)"

.PHONY: docker
docker: dist-prep
	docker build $(DOCKER_BUILD_ARGS) -t "bcdevices/$(PRJTAG)" .
	-@docker rm -f "$(PRJTAG)-$(VERSION_TAG)" 2>/dev/null
	docker run  $(DOCKER_RUN_ARGS) --name "$(PRJTAG)-$(VERSION_TAG)"  -t "bcdevices/$(PRJTAG)" \
	 /bin/bash -c "make build dist"
	docker cp "$(PRJTAG)-$(VERSION_TAG):/usr/src/dist" $(BASE_PATH)
