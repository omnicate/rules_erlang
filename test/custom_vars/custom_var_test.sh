set -ex

cat custom_vars/custom_var

grep -E 'OTP_VERSION: [0-9]+\.[0-9]+' custom_vars/custom_var
