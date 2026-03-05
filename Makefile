# Docker Socket Proxy - Home Assistant add-on
# Copyright (C) 2025 Fergus Stevens
#
# SPDX-License-Identifier: GPL-3.0-or-later

.PHONY: all setup lint test build clean

all: lint test build

setup:
	pip install pre-commit
	pre-commit install

lint:
	pre-commit run --all-files

test:
	./tests/test_addon.sh

build:
	docker build \
		--build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.21 \
		-t socket-proxy-test \
		socket-proxy/

clean:
	docker rmi socket-proxy-test 2>/dev/null || true
