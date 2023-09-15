#!/bin/env bash

# This script assumes a role and exports the credentials to the parent shell

set -a

# Parse arguments
verbose_level=0
while (( "$#" )); do
    case "$1" in
        -r|--role-arn)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                role_arn=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        -p|--profile)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                profile=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        -v|--verbose)
            verbose_level=$((verbose_level+1))
            shift 1
            ;;
        -q|--quiet)
            quiet=true
            shift 1
            ;;
        -*|--*=)
            echo "Error: Unsupported flag $1" >&2
            exit 1
            ;;
        *)
            shift
            ;;
    esac
done

function argument_checks() {
    # Check if role_arn is set, if not, exit and print usage
    if [ -z "$role_arn" ]; then
        # echo "Usage: $0 -r role_arn or $0 --role-arn role_arn [-p profile or --profile profile] [-v or --verbose]"
        exit 1
    fi

    # Use profile is empty, but AWS_PROFILE is set, use AWS_PROFILE
    if [ -z "$profile" ] && [ -n "$AWS_PROFILE" ]; then
        profile=$AWS_PROFILE
        echo "unset AWS_PROFILE"
    # Use profile is empty, and AWS_PROFILE is empty, use default
    elif [ -z "$profile" ] && [ -z "$AWS_PROFILE"]; then
        profile="default"
    fi

    # If verbose is greater than 0, set -x
    if [ $verbose_level -gt 0 ]; then
        set -x
    fi

    # If quiet is set, verbose_level should be 0
    if [ "$quiet" = true ]; then
        verbose_level=0
    fi
}


function save_allexport_option_global() {
    # Check the current state of the allexport option
    # Only need to run once, then you can call restore_allexport_option_global
    if [[ $- == *a* ]]; then
        was_export_all=true
    else
        was_export_all=false
    fi
}

function set_export_all_vars() {
    # Set the allexport option to export all variables to parent shell
    # equivilant of `set -o allexport`
    set -a
}

function restore_allexport_option_global() {
    # Restore the allexport option to its original state
    if ! $was_export_all; then
        set +a
    fi
}

function display_caller_identity() {
    # echo -e "\n"
    aws sts --profile "${profile}" get-caller-identity --output yaml
}

function save_and_clear_aws_env_vars() {
    for var in $(compgen -e); do
        if [[ $var == AWS_* ]]; then
            local "local_$var"="${!var}"
            set -x
            unset "$var"
            set +x
        fi
    done
}

function restore_aws_env_vars() {
    for var in $(compgen -v); do
        if [[ $var == local_AWS_* ]]; then

            export "${var#local_}"="${!var}"
            unset "$var"
        fi
    done
}

function assume_role(){
    ROLE_ARN=$role_arn
    SESSION_NAME=$(uuidgen)

    assume_role=$(aws sts assume-role --profile "${profile}" --role-arn "${ROLE_ARN}" --role-session-name "${SESSION_NAME}" --output json)

    if [ $? -eq 0 ]; then

        export AWS_ACCESS_KEY_ID=$(echo $assume_role | grep -oP '"AccessKeyId": "\K[^"]+')
        export AWS_SECRET_ACCESS_KEY=$(echo $assume_role | grep -oP '"SecretAccessKey": "\K[^"]+')
        export AWS_SESSION_TOKEN=$(echo $assume_role | grep -oP '"SessionToken": "\K[^"]+')



        echo "export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
        echo "export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
        echo "export AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}"


        # restore_allexport_option_global
    else
        # echo "Failed to assume role: $ROLE_ARN"
        exit 1
    fi
}

save_allexport_option_global
set_export_all_vars
argument_checks
# echo -e "\n Current Role:"
# display_caller_identity
assume_role
# echo -e "\n New Role with unique Session:"
# display_caller_identity
# restore_allexport_option_global
