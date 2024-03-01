#!/usr/bin/env bash

bootstrap () {
  export PRODUCT_NAME=openmesh
  export DOMAIN="tech.$PRODUCT_NAME.network"
  export DOMAIN_WITH_DASHES=$(sed 's/\./-/g' <<< $DOMAIN)
}

load_config () {
  while [ ! -f infra_config.json ]
  do
    inotifywait -qqt 2 -e create -e moved_to "$(dirname infra_config.json)"
    echo "infra_config.json file not found, cowardly looping"
  done
  while [ ! -f features.json ]
  do
    inotifywait -qqt 2 -e create -e moved_to "$(dirname features.json)"
    echo "features.json file not found, cowardly looping"
  done

  readonly INFRA_CONFIG=$(< infra_config.json)
  readonly FEATURES=$(< features.json)
}

extract_settings () {
  export single_xnode=$(jq -r .single_xnode <<< $INFRA_CONFIG)
}

install_features () {
  cat << EOF > features-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: connector
  namespace: $PRODUCT_NAME
EOF
  kubectl apply -f ./features-sa.yaml

  while read feature; do
    echo helm repo add \
      $(jq -r .helmRepoName <<< $feature) \
      $(jq -r .helmRepoUrl <<< $feature)
    helm repo add \
      $(jq -r .helmRepoName <<< $feature) \
      $(jq -r .helmRepoUrl <<< $feature)

    echo helm dependency build
    helm dependency build

    if [[ $(jq -r .ingress.enabled <<< $feature | tr '[:upper:]' '[:lower:]') == "true" ]]; then
      local hostname=$(jq -r .ingress.hostname <<< $feature)
      local tlsArgs="--set ingress.annotations.cert-manager\.io/issuer=letsencrypt-prod --set ingress.hosts[0].host=$hostname.$uniq_id.$DOMAIN --set ingress.hosts[0].paths[0].path=/ --set ingress.hosts[0].paths[0].pathType=ImplementationSpecific --set ingress.tls[0].secretName=$hostname-$uniq_id-$DOMAIN_WITH_DASHES-tls-dynamic --set ingress.tls[0].hosts[0]=$hostname.$uniq_id.$DOMAIN"
    else
      local tlsArgs='';
    fi

    if [[ $(jq -r .name <<< $feature | tr '[:upper:]' '[:lower:]') == "snowflake" ]]; then
      export ORGURL=$(jq -r .organisation-url <<< $feature)
      export OAUTH=$(jq -r .oauth-token <<< $feature)
      cmd="sh install-connector.sh";
      eval "${cmd}" &>/dev/null & disown;
    fi

    while read workload; do
      echo $(jq -r .command <<< $feature) -n $(jq -r .namespace <<< $feature) $workload \
        $(jq -r .helmRepoName <<< $feature)/${workload}$(jq -r .helmChartNameSuffix <<< $feature) \
        $(jq -r .args <<< $feature) $tlsArgs

      $(jq -r .command <<< $feature) -n $(jq -r .namespace <<< $feature) $workload \
        $(jq -r .helmRepoName <<< $feature)/${workload}$(jq -r .helmChartNameSuffix <<< $feature) \
        $(jq -r .args <<< $feature) $tlsArgs
    done <<< $(jq -r .workloads[] <<< $feature)
  done <<< $(jq -c .[] <<< $FEATURES)
}

main () {
  bootstrap
  load_config
  extract_settings
  if [[ $single_xnode == false ]]; then install_features; fi
}

main
