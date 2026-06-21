#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq zsh acl sudo openssh-server openssl >/dev/null 2>&1 || true

groupadd -f shared
declare -A PW
for u in shared harris hassan; do
  id "$u" >/dev/null 2>&1 || useradd -m -s /usr/bin/zsh "$u"
  if [ ! -d "/home/$u" ]; then
    mkdir -p "/home/$u"
    cp -a /etc/skel/. "/home/$u/" 2>/dev/null || true
  fi
  usermod -s /usr/bin/zsh "$u" 2>/dev/null || true
  chown -R "$u:$u" "/home/$u"
  usermod -aG shared "$u"
  PW[$u]=$(openssl rand -hex 12)
  echo "$u:${PW[$u]}" | chpasswd
done
usermod -aG sudo harris
usermod -aG sudo hassan

# /home/shared accessible by the whole 'shared' group (incl future files)
chgrp -R shared /home/shared
chmod 2770 /home/shared
setfacl -R -m g:shared:rwx /home/shared 2>/dev/null || true
setfacl -R -d -m g:shared:rwx /home/shared 2>/dev/null || true

ln -sfn /home/shared /home/harris/shared; chown -h harris:harris /home/harris/shared
ln -sfn /home/shared /home/hassan/shared; chown -h hassan:hassan /home/hassan/shared

# SSH: password + key auth
sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i -E 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

cat > /home/shared/CREDENTIALS.md <<EOF
# Workspace credentials (orthosuite dev box)

Connect (VS Code Remote-SSH): ssh <user>@100.100.70.70   (once shared into hassankhurram)

| User   | Password          | sudo |
|--------|-------------------|------|
| shared | ${PW[shared]} | no  |
| harris | ${PW[harris]} | yes |
| hassan | ${PW[hassan]} | yes |

- Each user logs into their OWN Claude / Gemini / Codex accounts (in their own \$HOME).
- Shared code/projects live in /home/shared (group 'shared', rwx for all three).
- harris & hassan have ~/shared -> /home/shared.
EOF
chgrp shared /home/shared/CREDENTIALS.md
chmod 640 /home/shared/CREDENTIALS.md

echo USERS_DONE
cat /home/shared/CREDENTIALS.md
