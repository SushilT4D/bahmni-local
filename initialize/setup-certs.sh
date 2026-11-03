HOSTNAME=bhs-tech4dev.bahmni.in
ORGANIZATION=BHS

mkdir -p certs/ca certs/kafka

# Generate CA private key
openssl genrsa -out certs/ca/ca.key 4096

# Generate CA certificate (10 years)
openssl req -x509 -new -nodes \
  -key certs/ca/ca.key \
  -sha256 \
  -days 3650 \
  -out certs/ca/ca.crt \
  -subj "/C=IN/O=$ORGANIZATION/CN=$HOSTNAME"

cat > certs/kafka/san.cnf <<EOF
    [ req ]
    default_bits       = 2048
    distinguished_name = req_distinguished_name
    req_extensions     = req_ext
    prompt             = no

    [ req_distinguished_name ]
    C  = IN
    O  = $ORGANIZATION
    CN = $HOSTNAME

    [ req_ext ]
    subjectAltName = @alt_names

    [ alt_names ]
    DNS.1 = $HOSTNAME
EOF

# Generate server private key
openssl genrsa -out certs/kafka/kafka.key 2048

# Generate server certificate signing request
openssl req -new \
  -key certs/kafka/kafka.key \
  -out certs/kafka/kafka.csr \
  -config certs/kafka/san.cnf

# Generate server certificate
openssl x509 -req \
  -in certs/kafka/kafka.csr \
  -CA certs/ca/ca.crt \
  -CAkey certs/ca/ca.key \
  -CAcreateserial \
  -out certs/kafka/kafka.crt \
  -days 1095 \
  -sha256 \
  -extensions req_ext \
  -extfile certs/kafka/san.cnf

# Build Kafka keystore
openssl pkcs12 -export \
  -in certs/kafka/kafka.crt \
  -inkey certs/kafka/kafka.key \
  -certfile certs/ca/ca.crt \
  -name kafka \
  -out certs/kafka/kafka.keystore.p12 \
  -passout pass:keystore-password

# Build Kafka truststore (requires JDK with keytool installed)
keytool -importcert \
  -alias kafka-ca \
  -file certs/ca/ca.crt \
  -keystore certs/kafka/kafka.truststore.p12 \
  -storetype PKCS12 \
  -storepass truststore-password \
  -noprompt

# Inspect keystore 
keytool -list -v \
  -keystore certs/kafka/kafka.keystore.p12 \
  -storetype PKCS12 \
  -storepass keystore-password
