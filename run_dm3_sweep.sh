#!/bin/bash

# Usage: ./run_dm3_sweep.sh <carla_port> <gpu_id> [dry_run]

CARLA_PORT=${1:-2000}
GPU=${2:-0}
DRY_RUN=${3:-false}
LOG_ROOT="./logdir/sweep_$(date +%Y%m%d_%H%M%S)"

# Tasks to sweep over
TASKS=("carla_four_lane" "carla_right_turn_hard" "carla_left_turn_hard" "carla_roundabout" "carla_lane_merge")

# Observability modes to sweep over
OBS_MODES=("birdeye_raw" "birdeye_wpt" "birdeye_gt")

# Intention sharing levels
INTENTION_LEVELS=("none" "neighbor" "visible" "all")

# ArkAngel modes
ARKANGEL_MODES=("baseline" "arkangel" "patch-ra" "patch-la")

# Transmission error rates
ERROR_RATES=(0.0 0.2 0.5)

for task in "${TASKS[@]}"; do
  for obs_mode in "${OBS_MODES[@]}"; do
    for intent_level in "${INTENTION_LEVELS[@]}"; do
      for arkangel_mode in "${ARKANGEL_MODES[@]}"; do
        for error_rate in "${ERROR_RATES[@]}"; do

          LOGDIR="${LOG_ROOT}/${task}/${obs_mode}/${intent_level}/${arkangel_mode}/error_${error_rate}"
          echo "Running experiment: ${LOGDIR}"

          # Base command
          CMD="bash train_dm3.sh ${CARLA_PORT} ${GPU} --task ${task} --dreamerv3.logdir ${LOGDIR}"

          # Observability settings
          CMD="${CMD} --env.observation.enabled [camera,collision,${obs_mode}]"
          if [[ "${obs_mode}" == "birdeye_raw" || "${obs_mode}" == "birdeye_wpt" || "${obs_mode}" == "birdeye_gt" ]]; then
              CMD="${CMD} --env.observation.${obs_mode}.entities [roadmap,waypoints,ego_vehicle,background_vehicles]"
          fi

          # Intention sharing settings
          if [[ "${intent_level}" == "none" ]]; then
              # Default, no background waypoints
              :
          else
              if (( $(echo "${error_rate} > 0.0" | bc -l) )); then
                  CMD="${CMD} --env.observation.${obs_mode}.entities [roadmap,waypoints,error_background_waypoints,ego_vehicle,background_vehicles]"
                  CMD="${CMD} --env.observation.${obs_mode}.error_rate ${error_rate}"
              else
                  CMD="${CMD} --env.observation.${obs_mode}.entities [roadmap,waypoints,background_waypoints,ego_vehicle,background_vehicles]"
              fi
              CMD="${CMD} --env.observation.${obs_mode}.waypoint_obs ${intent_level}"
          fi

          # ArkAngel settings
          case ${arkangel_mode} in
            "baseline")
              CMD="${CMD} --dreamerv3.arkangel.enable=false --dreamerv3.arkangel.patch=none"
              ;;
            "arkangel")
              CMD="${CMD} --dreamerv3.arkangel.enable=true --dreamerv3.arkangel.patch=none"
              ;;
            "patch-ra")
              CMD="${CMD} --dreamerv3.arkangel.enable=true --dreamerv3.arkangel.patch=pixel"
              CMD="${CMD} --env.observation.enabled [camera,collision,${obs_mode},mask_fov]"
              ;;
            "patch-la")
              CMD="${CMD} --dreamerv3.arkangel.enable=true --dreamerv3.arkangel.patch=latent"
              CMD="${CMD} --env.observation.enabled [camera,collision,${obs_mode},mask_fov]"
              ;;
          esac

          # Print the command to be executed
          echo "-----------------------------------------------------------------"
          echo "Command to execute:"
          echo "${CMD}"
          echo "-----------------------------------------------------------------"

          if [ "${DRY_RUN}" = false ]; then
              eval ${CMD}
          fi

        done
      done
    done
  done
done

echo "Sweep script finished."