cmake_minimum_required(VERSION 3.16)
project(humanoid_linglong)

install(PROGRAMS
    scripts/run_driver_linglong.sh
    scripts/run_control_linglong.sh
    scripts/run_hmi_linglong.sh
    scripts/run_sim2sim_linglong.sh
    scripts/download_models_linglong.sh
    DESTINATION bin
)
