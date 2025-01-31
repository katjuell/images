#!/usr/bin/env bash

set -o errexit -o nounset -o errtrace -o pipefail -x

# Ref: https://www.kubeflow.org/docs/components/katib/hyperparameter/#installing-katib

NAMESPACE=kubeflow
KATIB_VERSION=0.15.0


function manifests() {
  # Get the directory path of this script
  SCRIPT_DIR=$(
  	cd "$(dirname "$0")"
  	pwd
  )


  envsubst < $SCRIPT_DIR/kubeflow-katib.yaml.tpl > $SCRIPT_DIR/kubeflow-katib.yaml
  cat $SCRIPT_DIR/kubeflow-katib.yaml
  cat <<EOF > kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/kubeflow/katib.git/manifests/v1beta1/installs/katib-standalone?ref=v${KATIB_VERSION}
images:
  - name: docker.io/kubeflowkatib/katib-controller
    newName: ${IMAGE_REPOSITORY_CONTROLLER}
    newTag: ${IMAGE_REPOSITORY_CONTROLLER_TAG}
  - name: docker.io/kubeflowkatib/katib-db-manager
    newName: ${IMAGE_REPOSITORY_DB_MANAGER}
    newTag: ${IMAGE_REPOSITORY_DB_MANAGER_TAG}
namespace: ${NAMESPACE}
EOF
}

manifests
kubectl apply -k .

kubectl rollout status -n ${NAMESPACE} deployment/katib-db-manager --timeout=200s 
kubectl rollout status -n ${NAMESPACE} deployment/katib-controller --timeout=200s 

kubectl delete configmap katib-config -n ${NAMESPACE} || true
kubectl create configmap katib-config -n ${NAMESPACE} --from-file $SCRIPT_DIR/kubeflow-katib.yaml

kubectl rollout restart -n ${NAMESPACE} deployment/katib-db-manager
kubectl rollout restart -n ${NAMESPACE} deployment/katib-controller

kubectl rollout status -n ${NAMESPACE} deployment/katib-db-manager --timeout=200s
kubectl rollout status -n ${NAMESPACE} deployment/katib-controller --timeout=200s
