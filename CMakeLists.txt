cmake_minimum_required(VERSION 3.16)
project(humanoid_linglong)

install(PROGRAMS
    scripts/run_linglong.sh
    scripts/configure_can_linglong.sh
    scripts/install_linglong_service.py
    scripts/run_driver_linglong.sh
    scripts/run_control_linglong.sh
    scripts/run_hmi_linglong.sh
    scripts/run_hmi_tui_linglong.sh
    scripts/run_sim2sim_linglong.sh
    scripts/download_models_linglong.sh
    DESTINATION bin
)

install(FILES services/linglong.service.in DESTINATION share/humanoid_linglong)
