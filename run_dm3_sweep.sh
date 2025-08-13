#!/bin/bash
# Usage: ./run_dm3_sweep.sh <carla_port> <gpu_id> [dry_run] [run_eval] [smoke] [smoke_steps]

CARLA_PORT=${1:-2000}
GPU=${2:-0}
DRY_RUN=${3:-false}
RUN_EVAL=${4:-true}
SMOKE=${5:-false}
SMOKE_STEPS=${6:-100}
LOG_ROOT="./logdir/sweep_$(date +%Y%m%d_%H%M%S)"

# Tasks to sweep over
TASKS=("carla_four_lane" "carla_right_turn_hard" "carla_left_turn_hard" "carla_roundabout" "carla_lane_merge")

# BEV streams to sweep over
BEV_STREAMS=("birdeye_raw" "birdeye_wpt" "birdeye_gt")

# Observability modes to sweep over
OBSERVABILITY_MODES=("full" "fov" "recursive_fov")

# Intention sharing levels
INTENTION_LEVELS=("none" "neighbor" "visible" "all")

# ArkAngel modes
ARKANGEL_MODES=("baseline" "arkangel" "patch-ra" "patch-la")

# Transmission error rates
ERROR_RATES=(0.0 0.2 0.5)

for task in "${TASKS[@]}"; do
  for bev_stream in "${BEV_STREAMS[@]}"; do
    for observability in "${OBSERVABILITY_MODES[@]}"; do
      for intent_level in "${INTENTION_LEVELS[@]}"; do
        for arkangel_mode in "${ARKANGEL_MODES[@]}"; do
          for error_rate in "${ERROR_RATES[@]}"; do

            LOGDIR="${LOG_ROOT}/${task}/${bev_stream}/${observability}/${intent_level}/${arkangel_mode}/error_${error_rate}"
            echo "Running experiment: ${LOGDIR}"
            mkdir -p "${LOGDIR}"

            # Base command
            CMD="bash train_dm3.sh ${CARLA_PORT} ${GPU} --task ${task} --dreamerv3.logdir ${LOGDIR}"

            # Observability settings
            CMD="${CMD} --env.observation.enabled='[camera,collision,${bev_stream}]'"
            CMD="${CMD} --env.observation.${bev_stream}.observability=${observability}"
            CMD="${CMD} --env.observation.${bev_stream}.entities='[roadmap,waypoints,ego_vehicle,background_vehicles]'"

            # Intention sharing settings
            if [[ "${intent_level}" != "none" ]]; then
              if [[ "${error_rate}" != "0.0" && "${error_rate}" != "0" ]]; then
                CMD="${CMD} --env.observation.${bev_stream}.entities='[roadmap,waypoints,error_background_waypoints,ego_vehicle,background_vehicles]'"
                CMD="${CMD} --env.observation.${bev_stream}.error_rate=${error_rate}"
              else
                CMD="${CMD} --env.observation.${bev_stream}.entities='[roadmap,waypoints,background_waypoints,ego_vehicle,background_vehicles]'"
              fi
              CMD="${CMD} --env.observation.${bev_stream}.waypoint_obs=${intent_level}"
            fi

            # ArkAngel settings (choose exactly one mode per run)
            case ${arkangel_mode} in
              "baseline")
                CMD="${CMD} --dreamerv3.arkangel.enable=false --dreamerv3.arkangel.patch=none"
                ;;
              "arkangel")
                CMD="${CMD} --dreamerv3.arkangel.enable=true --dreamerv3.arkangel.patch=none"
                ;;
              "patch-ra")
                CMD="${CMD} --dreamerv3.arkangel.enable=true --dreamerv3.arkangel.patch=pixel"
                CMD="${CMD} --env.observation.enabled='[camera,collision,${bev_stream},mask_fov]'"
                ;;
              "patch-la")
                CMD="${CMD} --dreamerv3.arkangel.enable=true --dreamerv3.arkangel.patch=latent"
                CMD="${CMD} --env.observation.enabled='[camera,collision,${bev_stream},mask_fov]'"
                ;;
            esac

            # Optional quick smoke test: run just a few steps and skip eval/saves
            if [ "${SMOKE}" = true ]; then
              CMD="${CMD} --dreamerv3.run.steps=${SMOKE_STEPS} --dreamerv3.run.save_every=100000000 --dreamerv3.run.eval_every=100000000 --dreamerv3.run.eval_initial=false --dreamerv3.run.eval_eps=0"
            fi

            echo "-----------------------------------------------------------------"
            echo "Command to execute:"
            echo "${CMD}"
            echo "-----------------------------------------------------------------"

            if [ "${DRY_RUN}" = false ]; then
              eval ${CMD}
              if [ "${RUN_EVAL}" = true ] && [ "${SMOKE}" = false ]; then
                CKPT=$(ls -t "${LOGDIR}"/checkpoint* 2>/dev/null | head -n1)
                if [ -n "${CKPT}" ]; then
                  EVAL_CMD="bash eval_dm3.sh ${CARLA_PORT} ${GPU} ${CKPT} --task ${task} --dreamerv3.logdir ${LOGDIR}/eval"
                  echo "Running evaluation: ${EVAL_CMD}"
                  eval ${EVAL_CMD}
                else
                  echo "No checkpoint found for evaluation in ${LOGDIR}"
                fi
              fi
            fi

          done
        done
      done
    done
  done
done

echo "Sweep script finished."