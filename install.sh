if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <cluster_name/id> <servicename> <vpn_filepath>"
    echo "   - <cluster_name/id>  : cluster_name or cluster_id"
    echo "   - <crn_service_name> : crn-service-name"
    echo "   - <vpn_filepath>     : Path to ovpn file provided by SOS team"
    exit 1
fi

CLUSTER_NAME_OR_ID="$1"
CRN_SERVICE_NAME="$2"
VPN_FILE_PATH="$3"

set -x
TYPE=$(ibmcloud ks cluster get -c ${CLUSTER_NAME_OR_ID} --output json |  grep type  | cut -d '"' -f 4 )
if [ "$TYPE" = "openshift" ]; then
  ibmcloud ks cluster config -c ${CLUSTER_NAME_OR_ID} -admin
else
  ibmcloud ks cluster config -c ${CLUSTER_NAME_OR_ID}
fi

# Get crn values of cluster.
CRN=$(ibmcloud ks cluster get -c ${CLUSTER_NAME_OR_ID} --output json | grep crn  | cut -d '"' -f 4 )
CRN_BASE=$(echo "${CRN}"| cut -d ':' -f 1,2,3,4)        # ex.: crn:v1:staging:public
CRN_BASE=$(echo "${CRN_BASE}":${CRN_SERVICE_NAME})      # ex.: crn:v1:staging:public:crn-service-name

CRN_CNAME=$(echo "${CRN}"| cut -d ':' -f 3)
CRN_CTYPE=$(echo "${CRN}"| cut -d ':' -f 4)
CRN_REGION=$(echo "${CRN}"| cut -d ':' -f 6)
ACCOUNT_ID=$(echo "${CRN}"| cut -d ':' -f 7)
ACCOUNT_ID_=${ACCOUNT_ID/\//_}                          # replacing '/' with '_' in account-id.
CLUSTER_ID=$(echo "${CRN}"| cut -d ':' -f 8)

SOS_ADMIN_W3ID=$(ibmcloud target --output json | grep user_email | cut -d '"' -f 4)

# create ibm-services-system namespace and crn-info-services configmap.
cat <<-EOF | kubectl apply -f -
apiVersion: v1
kind: List
items: 
  - apiVersion: v1
    kind: Namespace
    metadata:
      name: ibm-services-system
      labels:
        name: ibm-services-system

  - apiVersion: v1
    kind: ConfigMap
    data:
      CRN_BASE: ${CRN_BASE}
      CRN_CNAME: ${CRN_CNAME}                      # staging/bluemix/internal/customerID
      CRN_CTYPE: ${CRN_CTYPE}                      # public/dedicated/local
      CRN_REGION: ${CRN_REGION}                    # cluster region
      CRN_SCOPE: ${ACCOUNT_ID}                     # ibmcloud account_id
      CRN_SCOPE_: ${ACCOUNT_ID_}
      CRN_VERSION: v1                      
      CRN_RESOURCE_TYPE: worker
      CRN_SERVICE_NAME: ${CRN_SERVICE_NAME}        # crn-service-name
      CRN_SERVICE_INSTANCE: ${CLUSTER_ID}          # cluster-id
      SOS_ADMIN_W3ID: "${SOS_ADMIN_W3ID}"          # w3email
      SOS_OPERATOR_USAM_SYSTEM: "NONE"
      C_CODE: "ARMADA"
    metadata:
      name: crn-info-services
      namespace: ibm-services-system
EOF

# create secret from ovpn file.
kubectl create secret generic sos-vpn-secret -n ibm-services-system --from-file=${VPN_FILE_PATH}

# if openshift, apply privileged SCC.
if [ "$TYPE" = "openshift" ]; then
  oc adm policy add-scc-to-user privileged system:serviceaccount:ibm-services-system:default
fi

# enable csutil add-on.
ibmcloud ks cluster addon enable csutil -c ${CLUSTER_NAME_OR_ID}

# wait for kube-auditlog-forwarder-service to come up and configure webhook.
sleep 15
export AUDIT_WEBHOOK_IP=$(kubectl get services --namespace ibm-services-system -l resource=kube-auditlog-forwarder -o jsonpath="{.items[0].spec.clusterIP}")
export AUDIT_URL="http://${AUDIT_WEBHOOK_IP}:8080"

ibmcloud ks cluster master audit-webhook set --cluster ${CLUSTER_NAME_OR_ID} --remote-server ${AUDIT_URL}
ibmcloud ks cluster master refresh --cluster ${CLUSTER_NAME_OR_ID}
ibmcloud ks cluster master audit-webhook get --cluster ${CLUSTER_NAME_OR_ID}
