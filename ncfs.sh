#!/bin/bash

echo "Starting NCFS..."

# Function to retrieve variables from environment or config file
get_variable() {
    local variable_name="$1"
    local config_file="$2"
    local force="$3"

    if [ -n "${!variable_name}" ]; then
        selected_value="${!variable_name}"
    else
        if [ -f "$config_file" ]; then
            selected_value=$(jq -r ".$variable_name" "$config_file")
            if [ "$selected_value" == "null" ] || [ -z "$selected_value" ]; then
                if [ "$force" == true ]; then
                    echo "$variable_name not found in config file and environment variables. Exiting."
                    exit 1
                else
                    selected_value="_DEFAULT_VALUE_DO_NOT_USE_IT"
                fi
            fi
        else
            if [ "$force" == true ]; then
                echo "Config file not found and $variable_name not set in environment variables. Exiting."
                exit 1
            else
                selected_value="_DEFAULT_VALUE_DO_NOT_USE_IT"
            fi
        fi
    fi

    echo "$selected_value"
}

TCP_PORT=$(get_variable "TCP_PORT" "/app/config.json" true)
CLOUDFLARE_AUTH_EMAIL=$(get_variable "CLOUDFLARE_AUTH_EMAIL" "config.json" true)
CLOUDFLARE_API_KEY=$(get_variable "CLOUDFLARE_API_KEY" "config.json" true)
CLOUDFLARE_ZONE_ID=$(get_variable "CLOUDFLARE_ZONE_ID" "config.json" true)
CLOUDFLARE_CNAME_RECORD_NAME=$(get_variable "CLOUDFLARE_CNAME_RECORD_NAME" "config.json" true)
CLOUDFLARE_SRV_RECORD_NAME=$(get_variable "CLOUDFLARE_SRV_RECORD_NAME" "config.json" false)
CLOUDFLARE_SRV_RECORD_PREFIX=$(get_variable "CLOUDFLARE_SRV_RECORD_PREFIX" "config.json" false)

echo "Checking if CNAME record exists in Cloudflare..."
cname_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=CNAME&name=$CLOUDFLARE_CNAME_RECORD_NAME" \
	-H "X-Auth-Email: $CLOUDFLARE_AUTH_EMAIL" \
	-H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
	-H "Content-Type: application/json")

if [[ $cname_record == *"\"count\":0"* ]]; then
	echo "CNAME record does not exist in Cloudflare. You have to create it manually. Create a CNAME record in your Cloudflare dashboard and set the name to $CLOUDFLARE_CNAME_RECORD_NAME (you can put example.com to content for now)"
	exit 1
fi

cname_record_id=$(echo "$cname_record" | sed -E 's/.*"id":"(\w+)".*/\1/')

srv_record_id="_DEFAULT_VALUE_DO_NOT_USE_IT"

if [ "$CLOUDFLARE_SRV_RECORD_NAME" != "_DEFAULT_VALUE_DO_NOT_USE_IT" ]; then
	echo "Checking if SRV record exists in Cloudflare..."
	srv_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=SRV&name=_minecraft._tcp.$CLOUDFLARE_SRV_RECORD_NAME" \
		-H "X-Auth-Email: $CLOUDFLARE_AUTH_EMAIL" \
		-H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
		-H "Content-Type: application/json")

	if [[ $srv_record == *"\"count\":0"* ]]; then
		echo "SRV record does not exist in Cloudflare. You have to create it manually. Create a SRV record in your Cloudflare dashboard and set the name to _minecraft._tcp.$CLOUDFLARE_SRV_RECORD_NAME, port to $TCP_PORT, target to $CLOUDFLARE_CNAME_RECORD_NAME"
		exit 1
	fi

	srv_record_id=$(echo "$srv_record" | sed -E 's/.*"id":"(\w+)".*/\1/')
fi

echo "Starting bore command..."

if [ -z "$DOCKER_NETWORK" ]; then
	bore local -l 127.0.0.1 "$TCP_PORT" --to bore.pub > /tmp/bore_output.txt &
else
	bore local -l $DOCKER_NETWORK "$TCP_PORT" --to bore.pub > /tmp/bore_output.txt &
fi

echo /tmp/bore_output.txt

while ! grep -q 'bore\.pub:[0-9]\+' /tmp/bore_output.txt; do
	sleep 1
done

bore_host_port=$(grep -o 'bore\.pub:[0-9]\+' /tmp/bore_output.txt | cut -d':' -f2)
bore_host="bore.pub"

if [ -z "$bore_host_port" ]; then
    echo "Failed to retrieve bore.pub URL."
    exit 1
fi

echo "Tunnel established at $bore_host:$bore_host_port"

update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$cname_record_id" \
	-H "X-Auth-Email: $CLOUDFLARE_AUTH_EMAIL" \
	-H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
	-H "Content-Type: application/json" \
	--data "{\"type\":\"CNAME\",\"name\":\"$CLOUDFLARE_CNAME_RECORD_NAME\",\"content\":\"$bore_host\"}")

case "$update" in
*"\"success\":false"*)
	echo "CNAME record could not be updated in Cloudflare. $update"
	exit 1
	;;
esac

if [ "$CLOUDFLARE_SRV_RECORD_NAME" != "_DEFAULT_VALUE_DO_NOT_USE_IT" ]; then
	echo "Updating SRV record in Cloudflare..."
	update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$srv_record_id" \
		-H "X-Auth-Email: $CLOUDFLARE_AUTH_EMAIL" \
		-H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
		-H "Content-Type: application/json" \
		--data "{\"type\":\"SRV\",\"name\":\"$CLOUDFLARE_SRV_RECORD_PREFIX.$CLOUDFLARE_SRV_RECORD_NAME\",\"data\": {\"name\":\"$CLOUDFLARE_SRV_RECORD_NAME\",\"port\":$bore_host_port,\"proto\":\"_tcp\",\"service\":\"_minecraft\",\"target\":\"$CLOUDFLARE_CNAME_RECORD_NAME\"}}")

	case "$update" in
	*"\"success\":false"*)
		echo "SRV record could not be updated in Cloudflare. $update"
		exit 1
		;;
	esac
fi

echo "DNS records updated successfully."
echo "You can connect to your server using $CLOUDFLARE_CNAME_RECORD_NAME:$bore_host_port"

tail -f "/dev/null"

exit 0
