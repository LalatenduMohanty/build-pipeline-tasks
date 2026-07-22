#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob

# Created for task: buildah@0.11.0
# Creation time: 2026-07-01T14:43:22Z

main() {
    local -r pipeline_file=$1

    local kind
    kind=$(yq '.kind' "$pipeline_file")

    local pipeline_tasks

    case $kind in
        PipelineRun)
            echo "Processing PipelineRun $pipeline_file"

            if [[ $(yq '.spec.pipelineSpec != null' "$pipeline_file") == true ]]; then
                pipeline_tasks=$(find_pipelinetasks_referencing_buildah "$pipeline_file")
                if [[ -z "$pipeline_tasks" ]]; then
                    echo "PipelineRun $pipeline_file does not contain any buildah tasks"
                    return 0
                fi
            else
                # The user is running this script directly on a PipelineRun that references
                # an external Pipeline. Support an explicit override, fall back to defaults.
                pipeline_tasks=${BUILDAH_PIPELINE_TASKS:-"build-container build-images"}
            fi

            process_pipelinerun "$pipeline_file" "$pipeline_tasks"
            ;;
        Pipeline)
            echo "Processing Pipeline $pipeline_file"

            pipeline_tasks=$(find_pipelinetasks_referencing_buildah "$pipeline_file")
            if [[ -z "$pipeline_tasks" ]]; then
                echo "Pipeline $pipeline_file does not contain any buildah tasks"
                return 0
            fi

            echo "Looking for PipelineRuns that reference Pipeline $pipeline_file"
            find_pipelineruns_referencing_pipeline "$pipeline_file" | while read -r plr_file; do
                echo "Processing PipelineRun $plr_file"
                process_pipelinerun "$plr_file" "$pipeline_tasks"
            done
            ;;
        *)
            echo "$pipeline_file is neither a PipelineRun nor a Pipeline, aborting"
            return 0
            ;;
    esac
}

find_pipelinetasks_referencing_buildah() {
    local -r pipeline_or_pipelinerun_file=$1
    yq '
        (.spec.tasks[]?, .spec.pipelineSpec.tasks[]?) |
        select(
            .taskRef.params != null and
            .taskRef.params | any_c(
                .name == "name" and (
                    .value == "buildah" or
                    .value == "buildah-remote" or
                    .value == "buildah-oci-ta" or
                    .value == "buildah-remote-oci-ta" or
                    .value == "buildah-oci-ta-min"
                )
            )
        ) |
        .name
    ' "$pipeline_or_pipelinerun_file"
}

find_pipelineruns_referencing_pipeline() {
    local -r pipeline_file=$1

    local name
    name=$(yq '.metadata.name' "$pipeline_file")

    local dir=${pipeline_file%/*}
    local matches_pipeline
     # Support the common case of Pipelines in the .tekton/ directory alongside PipelineRuns
    for f in "$dir"/*.yaml; do
        matches_pipeline=$(
            pipeline_name=$name yq '
                .kind == "PipelineRun" and .spec.pipelineRef.name == env(pipeline_name)
            ' "$f"
        )
        if [[ "$matches_pipeline" == true ]]; then
            echo "$f"
        fi
    done
}

process_pipelinerun() {
    local -r pipelinerun_file=$1
    local -r pipeline_tasks=$2

    for task_name in $pipeline_tasks; do
        echo "Processing overrides for pipelineTask $task_name"
        handle_sbom_syft_generate_override "$pipelinerun_file" "$task_name"
        handle_push_override "$pipelinerun_file" "$task_name"
    done
}

handle_sbom_syft_generate_override() {
    local -r pipelinerun_file=$1
    local -r task_name=$2

    if ! has_step_override "$pipelinerun_file" "$task_name" "sbom-syft-generate"; then
        echo "No sbom-syft-generate step overrides found"
        return 0
    fi

    if any_arch_builds_in_cluster "$pipelinerun_file"; then
        align_sbom_and_build_resources "$pipelinerun_file" "$task_name"
    else
        echo "None of the builds for this multiarch PipelineRun run in-cluster, no resource alignment needed"
    fi

    delete_step_override "$pipelinerun_file" "$task_name" "sbom-syft-generate"
}

handle_push_override() {
    local -r pipelinerun_file=$1
    local -r task_name=$2

    if ! has_step_override "$pipelinerun_file" "$task_name" "push"; then
        echo "No push step overrides found"
        return 0
    fi

    # No resource alignment needed, build step resources should always be enough for pushing.
    # Just delete the overrides.
    delete_step_override "$pipelinerun_file" "$task_name" "push"
}

has_step_override() {
    local -r pipelinerun_file=$1
    local -r task_name=$2
    local -r step_name=$3

    has_override=$(
        taskname=$task_name stepname=$step_name yq '
            .spec.taskRunSpecs != null and .spec.taskRunSpecs |
            any_c(
                .pipelineTaskName == env(taskname) and
                .stepSpecs | any_c(.name == env(stepname))
            )
        ' "$pipelinerun_file"
    )

    [[ $has_override == true ]]
}

any_arch_builds_in_cluster() {
    local -r pipelinerun_file=$1

    local platforms
    readarray -t platforms < <(
        yq '.spec.params[] | select(.name == "build-platforms") | .value[]' "$pipelinerun_file"
    )

    if [[ ${#platforms[@]} -eq 0 ]]; then
        # single-arch build in cluster
        return 0
    fi

    for platform in "${platforms[@]}"; do
        case "$platform" in
            # based on local-platforms values in redhat-appstudio/infra-deployments
            localhost|local|linux/x86_64) return 0 ;;
        esac
    done

    return 1
}

align_sbom_and_build_resources() {
    local -r pipelinerun_file=$1
    local -r task_name=$2

    local build_resources sbom_resources
    build_resources=$(get_step_override_resources "$pipelinerun_file" "$task_name" build)
    sbom_resources=$(get_step_override_resources "$pipelinerun_file" "$task_name" sbom-syft-generate)

    local build_mem_request build_mem_limit build_cpu_request build_cpu_limit
    build_mem_request=$(default=8Gi yq '.requests.memory // env(default)' <<< "$build_resources")
    build_mem_limit=$(default=8Gi yq '.limits.memory // env(default)' <<< "$build_resources")
    build_cpu_request=$(default=4600m yq '.requests.cpu // env(default)' <<< "$build_resources")
    build_cpu_limit=$(default=4600m yq '.limits.cpu // env(default)' <<< "$build_resources")

    local sbom_mem_request sbom_mem_limit sbom_cpu_request sbom_cpu_limit
    sbom_mem_request=$(default=4Gi yq '.requests.memory // env(default)' <<< "$sbom_resources")
    sbom_mem_limit=$(default=4Gi yq '.limits.memory // env(default)' <<< "$sbom_resources")
    sbom_cpu_request=$(default=1100m yq '.requests.cpu // env(default)' <<< "$sbom_resources")
    sbom_cpu_limit=$(default=1100m yq '.limits.cpu // env(default)' <<< "$sbom_resources")

    local new_resources=$build_resources
    local changed=false

    if mem_less_than "$build_mem_request" "$sbom_mem_request"; then
        new_resources=$(value=$sbom_mem_request yq '.requests.memory = strenv(value)' <<< "$new_resources")
        changed=true
    fi
    if mem_less_than "$build_mem_limit" "$sbom_mem_limit"; then
        new_resources=$(value=$sbom_mem_limit yq '.limits.memory = strenv(value)' <<< "$new_resources")
        changed=true
    fi
    if cpu_less_than "$build_cpu_request" "$sbom_cpu_request"; then
        new_resources=$(value=$sbom_cpu_request yq '.requests.cpu = strenv(value)' <<< "$new_resources")
        changed=true
    fi
    if cpu_less_than "$build_cpu_limit" "$sbom_cpu_limit"; then
        new_resources=$(value=$sbom_cpu_limit yq '.limits.cpu = strenv(value)' <<< "$new_resources")
        changed=true
    fi

    if [[ $changed == false ]]; then
        echo "sbom-syft-generate resources are <= build resources, not updating build step overrides"
    elif [[ -z "$build_resources" ]]; then
        # PipelineRun didn't have overrides for build step,
        # add new stepSpec to the same array that had the sbom-syft-generate override
        echo "Adding build step overrides to taskRunSpecs"
        local stepspecs_array_path
        stepspecs_array_path=$(
            taskname=$task_name yq -o json --indent 0 '
                .spec.taskRunSpecs[]? |
                select(.pipelineTaskName == env(taskname)) |
                .stepSpecs |
                select(. != null and any_c(.name == "sbom-syft-generate")) |
                path
            ' "$pipelinerun_file"
        )
        local build_stepspec
        build_stepspec=$(yq '{"name": "build", "computeResources": .}' <<< "$new_resources")
        pmt modify -f "$pipelinerun_file" generic insert "$stepspecs_array_path" "$build_stepspec"
    else
        echo "Updating existing build step overrides"
        local build_stepspec_resources_path
        build_stepspec_resources_path=$(
            taskname=$task_name yq -o json --indent 0 '
                .spec.taskRunSpecs[]? |
                select(.pipelineTaskName == env(taskname)) |
                .stepSpecs[]? |
                select(.name == "build") |
                .computeResources |
                path
            ' "$pipelinerun_file"
        )
        pmt modify -f "$pipelinerun_file" generic replace "$build_stepspec_resources_path" "$new_resources"
    fi
}

get_step_override_resources() {
    local -r pipelinerun_file=$1
    local -r task_name=$2
    local -r step_name=$3

    taskname=$task_name stepname=$step_name yq '
        .spec.taskRunSpecs[]? |
        select(.pipelineTaskName == env(taskname)) |
        .stepSpecs[]? |
        select(.name == env(stepname)) |
        .computeResources
    ' "$pipelinerun_file"
}

# Return 0 if the first argument represents a smaller amount of memory than the second, else 1.
#
# Uses numfmt --from=auto to convert memory strings, which should support all the suffixes
# (https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#meaning-of-memory)
# except for m (milli), which no sane person would use for memory.
#
# numfmt is part of coreutils, so we can reasonably expect it to be available everywhere.
mem_less_than() {
    [[ "$(numfmt --from=auto "$1")" -lt "$(numfmt --from=auto "$2")" ]]
}

# Return 0 if the first argument represents a smaller amount of cpu than the second, else 1.
#
# Supports the m (milli) suffix and fractional values.
cpu_less_than() {
    local a=$1
    local b=$2

    # Do all math using yq, need a tool that does floating point math and is guaranteed available
    if [[ $a == *m ]]; then
        a=$(yq '. * 0.001' <<< "${a%m}")
    fi
    if [[ $b == *m ]]; then
        b=$(yq '. * 0.001' <<< "${b%m}")
    fi

    local is_lt
    is_lt=$(yq '.[0] < .[1]' <<< "[$a, $b]")
    [[ $is_lt == true ]]
}

delete_step_override() {
    local -r pipelinerun_file=$1
    local -r task_name=$2
    local -r step_name=$3

    echo "Removing $step_name step overrides"
    local stepspec_path
    stepspec_path=$(
        taskname=$task_name stepname=$step_name yq -o json --indent 0 '
            .spec.taskRunSpecs[]? |
            select(.pipelineTaskName == env(taskname)) |
            .stepSpecs[]? |
            select(.name == env(stepname)) |
            path
        ' "$pipelinerun_file"
    )
    pmt modify -f "$pipelinerun_file" generic remove "$stepspec_path"

    # If the removal removed everything except pipelineTaskName, remove the entire object
    local empty_taskspec_path
    empty_taskspec_path=$(
        taskname=$task_name yq -o json --indent 0 '
            .spec.taskRunSpecs[]? |
            select(.pipelineTaskName == env(taskname)) |
            select((keys | length) == 1) |
            path
        ' "$pipelinerun_file"
    )
    if [[ -n "$empty_taskspec_path" ]]; then
        echo "Removing $task_name taskRunSpec entirely because it's empty"
        pmt modify -f "$pipelinerun_file" generic remove "$empty_taskspec_path"
    fi
}

main "${1?missing pipeline file}"
