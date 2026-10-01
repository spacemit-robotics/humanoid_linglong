#!/bin/bash
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
CONNECTION="${OPERATOR_CONNECTION:-${XDG_STATE_HOME:-$HOME/.local/state}/humanoid-operator/linglong/connection.json}"
exec hmi_tui --connection "$CONNECTION" "$@"
