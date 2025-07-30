


log_step " ⚙️ Updating YAML files with the following info:"
echo ""

log_info "----------------------------------------"
log_info "Management IP Address: $MGMT_IP_ADDR"
log_info "WAN IP Address: $USER_WAN_IP_ADDR"
log_info "MCC: $MCC"
log_info "MNC: $MNC"
log_info "TAC: $TAC_NUM"
log_info "----------------------------------------"

log_info "Backing up existing YAML files..."
cp /etc/open5gs/amf.yaml /etc/open5gs/amf.yaml.bak
cp /etc/open5gs/sgwu.yaml /etc/open5gs/sgwu.yaml.bak
cp /etc/open5gs/mme.yaml /etc/open5gs/mme.yaml.bak
cp /etc/open5gs/upf.yaml /etc/open5gs/upf.yaml.bak
cp /etc/open5gs/nrf.yaml /etc/open5gs/nrf.yaml.bak
cp /etc/open5gs/smf.yaml /etc/open5gs/smf.yaml.bak
cp /etc/open5gs/sgwc.yaml /etc/open5gs/sgwc.yaml.bak

export MGMT_IP_ADDR="$MGMT_IP_ADDR"
export USER_WAN_IP_ADDR="$USER_WAN_IP_ADDR"
export MCC="$MCC"
export MNC="$MNC"
export TAC_NUM="$TAC_NUM"

log_info "✏️  Editing amf.yaml ..."
yq -y '
  .amf.ngap.server[0].address = env.MGMT_IP_ADDR |
  .amf.guami[0].plmn_id.mcc = (env.MCC | tonumber) |
  .amf.guami[0].plmn_id.mnc = (env.MNC | tonumber) |
  .amf.tai[0].plmn_id.mcc = (env.MCC | tonumber) |
  .amf.tai[0].plmn_id.mnc = (env.MNC | tonumber) |
  .amf.tai[0].tac = (env.TAC_NUM | tonumber) |
  .amf.plmn_support[0].plmn_id.mcc = (env.MCC | tonumber) |
  .amf.plmn_support[0].plmn_id.mnc = (env.MNC | tonumber)
' /etc/open5gs/amf.yaml > /etc/open5gs/amf.yaml.new && mv /etc/open5gs/amf.yaml.new /etc/open5gs/amf.yaml

log_info "✏️  Editing sgwu.yaml ..."
yq -y '
  .sgwu.gtpu.server[0].address = env.MGMT_IP_ADDR
' /etc/open5gs/sgwu.yaml > /etc/open5gs/sgwu.yaml.new && mv /etc/open5gs/sgwu.yaml.new /etc/open5gs/sgwu.yaml

log_info "✏️  Editing mme.yaml ..."
yq -y '
  .mme.s1ap.server[0].address = env.MGMT_IP_ADDR |
  .mme.gtpc.client.sgwc[0].address = "127.0.0.5" |
  .mme.gummei[0].plmn_id.mcc = (env.MCC | tonumber) |
  .mme.gummei[0].plmn_id.mnc = (env.MNC | tonumber) |
  .mme.tai[0].plmn_id.mcc = (env.MCC | tonumber) |
  .mme.tai[0].plmn_id.mnc = (env.MNC | tonumber) |
  .mme.tai[0].tac = (env.TAC_NUM | tonumber)
' /etc/open5gs/mme.yaml > /etc/open5gs/mme.yaml.new && mv /etc/open5gs/mme.yaml.new /etc/open5gs/mme.yaml

log_info "✏️  Editing upf.yaml ..."
yq -y '
  .upf.pfcp.server[0].address = "127.0.0.7" |
  .upf.gtpu.server[0].address = env.USER_WAN_IP_ADDR
' /etc/open5gs/upf.yaml > /etc/open5gs/upf.yaml.new && mv /etc/open5gs/upf.yaml.new /etc/open5gs/upf.yaml


log_info "✏️  Editing nrf.yaml ..."
yq -y '
  .nrf.serving[0].plmn_id.mcc = (env.MCC | tonumber) |
  .nrf.serving[0].plmn_id.mnc = (env.MNC | tonumber) |
  .nrf.sbi.server[0].address = "127.0.0.200"
' /etc/open5gs/nrf.yaml > /etc/open5gs/nrf.yaml.new && mv /etc/open5gs/nrf.yaml.new /etc/open5gs/nrf.yaml

log_info "✏️  Editing smf.yaml ..."
yq -y '
  .smf.pfcp.server[0].address = "127.0.0.4" |
  .smf.pfcp.client.upf[0].address = "127.0.0.7" |
  .smf.gtpc.server[0].address = "127.0.0.4" |
  .smf.gtpu.server[0].address = "127.0.0.4" |
  .smf.metrics.server[0].address = "127.0.0.4" |
  .smf.sbi.server[0].address = "127.0.0.4" |
  .smf.sbi.server[0].port = 7777 |
  .smf.sbi.client = {"nrf": [{"uri": "http://127.0.0.200:7777"}]}
' /etc/open5gs/smf.yaml > /etc/open5gs/smf.yaml.new && mv /etc/open5gs/smf.yaml.new /etc/open5gs/smf.yaml

log_info "✏️  Editing sgwc.yaml ..."

yq -y '
  .sgwc.pfcp.server[0].address = "127.0.0.5" |
  .sgwc.pfcp.client.sgwu[0].address = "127.0.0.6" |
  .sgwc.gtpc.server[0].address = "127.0.0.5"
' /etc/open5gs/sgwc.yaml > /etc/open5gs/sgwc.yaml.new && mv /etc/open5gs/sgwc.yaml.new /etc/open5gs/sgwc.yaml


log_info "🚀 YAML files edited successfully!"
