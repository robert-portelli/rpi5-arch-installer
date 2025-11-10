# 'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

# First boot identity (idempotent defaults)
  #--root-password-locked \
systemd-firstboot \
  --root="${config[ROOT_MNT]}" \
  --locale="${config[LOCALE]}" \
  --keymap="${config[KEYMAP]}" \
  --timezone="${config[TZ]}" \
  --hostname="${config[HOSTNAME]}" \
  --setup-machine-id \
  --delete-root-password --force # for boot testing only
