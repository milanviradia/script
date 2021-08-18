if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <cluster_name/id>"
    exit 1
fi

CLUSTER_NAME_OR_ID="$1"

ibmcloud ks cluster config --cluster ${CLUSTER_NAME_OR_ID}

TYPE=$(ibmcloud ks cluster get --cluster ${CLUSTER_NAME_OR_ID} --output json |  grep type  | cut -d '"' -f 4 )
if [ "$TYPE" = "openshift" ]; then
  ibmcloud ks cluster config --cluster ${CLUSTER_NAME_OR_ID} -admin
fi

# disable csutil add-on.
ibmcloud ks cluster addon disable csutil -f --cluster ${CLUSTER_NAME_OR_ID}

# delete ibm-services-system namespace.
kubectl delete ns ibm-services-system --ignore-not-found
