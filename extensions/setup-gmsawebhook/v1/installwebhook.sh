#!/usr/bin/env bash

#https://github.com/kubernetes-sigs/windows-gmsa/tree/master/admission-webhook/deploy has webhook installion for gmsa 
# as per Kubernetes documentatin https://kubernetes.io/docs/tasks/configure-pod-container/configure-gmsa/



download_install_gmsa_crd() {
	local URL="https://raw.githubusercontent.com/valakhin/aquila-aks-extensions/master/extensions/setup-gmsawebhook/v1/gmsa-crd.yaml"
	if which curl &> /dev/null; then
	   curl -sL "$URL" > "gmsa-crd.yaml"
	else
	   wget -O "gmsa-crd.yaml" "$URL"
	fi

	#local CRD_MANIFEST_PATH=$(ensure_helper_file_present 'gmsa-crd.yml')
	#local CRD_MANIFEST_CONTENTS=$(cat "$CRD_MANIFEST_PATH")
	if kubectl get crd gmsacredentialspecs.windows.k8s.io &> /dev/null; then
		kubectl delete crd gmsacredentialspecs.windows.k8s.io
	fi
	kubectl create -f gmsa-crd.yaml
	
}	

download_deploy_gmsa_webhook() {

local URL="https://raw.githubusercontent.com/kubernetes-sigs/windows-gmsa/master/admission-webhook/deploy/deploy-gmsa-webhook.sh"

if which curl &> /dev/null; then
   curl -sL "$URL" > "deploy-gmsa-webhook.sh"
else
   wget -O "deploy-gmsa-webhook.sh" "$URL"
fi

chmod +777 deploy-gmsa-webhook.sh

./deploy-gmsa-webhook.sh ~/.kube/gmsa-webhook-manifest.yaml

}

# Create gmsa CRD
download_install_gmsa_crd

#deploy gmsa webhook
download_deploy_gmsa_webhook

