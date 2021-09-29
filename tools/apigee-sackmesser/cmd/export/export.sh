#!/bin/bash
# shellcheck disable=SC2154
# SC2154: Variables are sent in ../../bin/sackmesser

# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# <http://www.apache.org/licenses/LICENSE-2.0>
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

SCRIPT_FOLDER=$( (cd "$(dirname "$0")" && pwd ))
source "$SCRIPT_FOLDER/../../lib/logutils.sh"

mgmtAPIDownload() {
    loginfo "Sackmesser export (zip) $1"
    curl -fsS -H "Authorization: Bearer $token" "https://$baseuri/v1/$1" -o "$2"
}

urlencode() {
    echo "\"${*:1}\"" | jq -r '@uri'
}

export export_folder="$PWD/$organization"

if [ -d "$export_folder" ]; then
    logerror "Folder $export_folder already exists. Please remove/rename and try again."
    exit 1
fi

loginfo "exporting to $export_folder"
mkdir -p "$export_folder"

sackmesser list "organizations/$organization/sharedflows" | jq -r -c '.[]|.'| while read -r sharedflow; do
    loginfo "download shared flow: $sharedflow"
    mkdir -p "$export_folder/sharedflows/$sharedflow"
    latest="$(sackmesser list "organizations/$organization/sharedflows/$sharedflow" | jq '.revision | max | tonumber')"
    mgmtAPIDownload "organizations/$organization/sharedflows/$sharedflow/revisions/$latest?format=bundle" "$export_folder/sharedflows/$sharedflow/bundle.zip"
    unzip -q "$export_folder/sharedflows/$sharedflow/bundle.zip" -d "$export_folder/sharedflows/$sharedflow"
    rm "$export_folder/sharedflows/$sharedflow/bundle.zip"
done

sackmesser list "organizations/$organization/apis" | jq -r -c '.[]|.' | while read -r proxy; do
    loginfo "download proxy: $proxy"
    mkdir -p "$export_folder/proxies/$proxy"
    latest="$(sackmesser list "organizations/$organization/apis/$proxy" | jq '.revision | max | tonumber')"
    mgmtAPIDownload "organizations/$organization/apis/$proxy/revisions/$latest?format=bundle" "$export_folder/proxies/$proxy/bundle.zip"
    unzip -q "$export_folder/proxies/$proxy/bundle.zip" -d "$export_folder/proxies/$proxy"
    rm "$export_folder/proxies/$proxy/bundle.zip"
done

loginfo "Org Export to: $export_folder/orgConfig/resources/edge/org"
mkdir -p "$export_folder/orgConfig/resources/edge/org"

mkdir -p "$export_folder/temp/developers"
mkdir -p "$export_folder/temp/apps"

sackmesser list "organizations/$organization/developers" | jq -r -c '.[]|.' | while read -r email; do
    loginfo "download developer: $email"
    sackmesser list "organizations/$organization/developers/$email" > "$export_folder/temp/developers/$email".json
    mkdir -p "$export_folder/temp/developerApps/$email"
    sackmesser list "organizations/$organization/developers/$email/apps" | jq -r -c '.[]|.' | while read -r appId; do
        loginfo "download developer app: $appId for developer: $email"
        sackmesser list "organizations/$organization/developers/$email/apps/$(urlencode "$appId")" > "$export_folder/temp/developerApps/$email/$appId".json
    done

    if ls "$export_folder/temp/developerApps/$email"/*.json 1> /dev/null 2>&1; then
        jq -n "{ \"$email\": [inputs] }" "$export_folder/temp/developerApps/$email"/*.json > "$export_folder/temp/apps/$email.json"
    else
        loginfo "No Apps for Developer: $email"
    fi
done


jq -n '[inputs]' "$export_folder/temp/developers"/*.json > "$export_folder/orgConfig/resources/edge/org/developers.json"
jq -n '[inputs]' "$export_folder/temp/apps"/*.json > "$export_folder/orgConfig/resources/edge/org/apps.json"


mkdir -p "$export_folder/temp/apiproducts"
sackmesser list "organizations/$organization/apiproducts" | jq -r -c '.[]|.' | while read -r product; do
    loginfo "download API product: $product"
    sackmesser list "organizations/$organization/apiproducts/$(urlencode "$product")" > "$export_folder/temp/apiproducts/$product".json
done
jq -n '[inputs]' "$export_folder/temp/apiproducts"/*.json > "$export_folder/orgConfig/resources/edge/org/apiProducts.json"


sackmesser list "organizations/$organization/keyvaluemaps" > "$export_folder"/orgConfig/resources/edge/org/kvms.json

sackmesser list "organizations/$organization/environments" | jq -r -c '.[]|.' | while read -r env; do

    loginfo "Env Export to: $export_folder/orgConfig/resources/edge/env/$env"
    mkdir -p "$export_folder/orgConfig/resources/edge/env/$env"

    mkdir -p "$export_folder/temp/$env"/flowhooks
    sackmesser list "organizations/$organization/environments/$env/flowhooks" | jq -r -c '.[]|.' | while read -r fh; do
        sackmesser list "organizations/$organization/environments/$env/flowhooks/$fh" | jq '.' > "$export_folder/temp/$env/flowhooks/$fh".json
    done
    jq -n '[inputs]' "$export_folder/temp/$env/flowhooks/"/*.json > "$export_folder/orgConfig/resources/edge/env/$env/flowhooks.json"

    sackmesser list "organizations/$organization/environments/$env/keyvaluemaps" > "$export_folder/orgConfig/resources/edge/env/$env"/kvms.json

    mkdir -p "$export_folder/temp/$env"/targetservers
    sackmesser list "organizations/$organization/environments/$env/targetservers" | jq -r -c '.[]|.' | while read -r targetserver; do
        sackmesser list "organizations/$organization/environments/$env/targetservers/$(urlencode "$targetserver")" | jq '.' > "$export_folder/temp/$env/targetservers/${targetserver/ /-}".json
    done
    jq -n '[inputs]' "$export_folder/temp/$env/targetservers/"/*.json > "$export_folder/orgConfig/resources/edge/env/$env/targetservers.json"


    mkdir -p "$export_folder/temp/$env"/keystores
    mkdir -p "$export_folder/temp/$env"/aliases
    sackmesser list "organizations/$organization/environments/$env/keystores" | jq -r -c '.[]|.' | while read -r keystore; do
        keystore_uri="organizations/$organization/environments/$env/keystores/$(urlencode "$keystore")"
        sackmesser list "$keystore_uri" | jq '.' >  "$export_folder/temp/$env/keystores/${keystore/ /-}".json
        sackmesser list "$keystore_uri"/aliases | jq -r -c '.[]|.' | while read -r alias; do
            sackmesser list "$keystore_uri/aliases/$alias" > "$export_folder/temp/$env/aliases/$alias".json
        done
    done
    jq -n '[inputs]' "$export_folder/temp/$env/keystores/"/*.json > "$export_folder/orgConfig/resources/edge/env/$env/keystores.json"
    jq -n '[inputs]' "$export_folder/temp/$env/aliases/"/*.json > "$export_folder/orgConfig/resources/edge/env/$env/aliases.json"
done

loginfo "Export Done: see $export_folder"