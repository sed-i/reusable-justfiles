# How to use this justfile?
# multipass launch noble --name charm-dev --memory 16G --cpus 8 --disk 100G
# multipass shell charm-dev
# sudo snap install --classic just
# sudo just -f ubuntu-24.04.just charm-dev


@_banner:
  echo "======================================================================"
  echo " If you're feeling adventurous, you could help the charming community"
  echo " by switching to the beta channels and reporting any issues you "
  echo " encounter in you journey!"
  echo
  echo "   sudo snap refresh juju --channel=3/beta"
  echo "   sudo snap refresh charmcraft --classic --channel=3.x/beta"
  echo "======================================================================"


init:
  DEBIAN_FRONTEND=noninteractive apt remove -y landscape-client landscape-common adwaita-icon-theme humanity-icon-theme
  
  # Disable swap
  sysctl -w vm.swappiness=0
  grep -qxF 'vm.swappiness = 0' /etc/sysctl.conf || echo "vm.swappiness = 0" >> /etc/sysctl.conf
  swapoff -a

  # Disable unnecessary services
  systemctl disable man-db.timer man-db.service --now
  systemctl disable apport.service apport-autoreport.service  --now
  systemctl disable apt-daily.service apt-daily.timer --now
  systemctl disable apt-daily-upgrade.service apt-daily-upgrade.timer --now
  systemctl disable unattended-upgrades.service --now
  systemctl disable motd-news.service motd-news.timer --now
  systemctl disable bluetooth.target --now
  systemctl disable ua-timer.timer ua-timer.service --now
  systemctl disable systemd-tmpfiles-clean.timer --now

  # Disable IPv6
  grep -qxF 'net.ipv6.conf.all.disable_ipv6=1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.disable_ipv6=1' >> /etc/sysctl.conf
  grep -qxF 'net.ipv6.conf.default.disable_ipv6=1' /etc/sysctl.conf || echo 'net.ipv6.conf.default.disable_ipv6=1' >> /etc/sysctl.conf
  grep -qxF 'net.ipv6.conf.lo.disable_ipv6=1' /etc/sysctl.conf || echo 'net.ipv6.conf.lo.disable_ipv6=1' >> /etc/sysctl.conf
  
  sysctl -p


update:
  apt update


upgrade:
  DEBIAN_FRONTEND=noninteractive apt -y upgrade
  snap refresh


git:
  apt install -y git
  git config --global init.defaultBranch main
  git config --global pull.ff only

  # Aliases
  git config --global alias.alias "config --get-regexp alias"
  git config --global alias.adog "log --all --decorate --oneline --graph"
  git config --global alias.adam "!func(){ git add -u && git commit --amend --no-edit; }; func"
  git config --global alias.co checkout
  git config --global alias.st status
  git config --global alias.sdiff "difftool --staged --dir-diff"


utils: git
  DEBIAN_FRONTEND=noninteractive apt -y install python3-pip jq bat ripgrep kitty-terminfo tox
  snap install yq
  snap install astral-uv --classic


IPADDR := `ip -4 -j route get 2.2.2.2 | jq -r '.[] | .prefsrc'`
microk8s:
  snap install microk8s --channel=1.31-strict/stable
  snap alias microk8s.kubectl kubectl
  snap alias microk8s.kubectl k

  usermod -a -G snap_microk8s ${SUDO_USER:-$USER}
  microk8s status --wait-ready

  microk8s.enable metrics-server
  microk8s.kubectl rollout status deployments/metrics-server -n kube-system -w --timeout=600s

  # The dns addon will restart the api server so you may see a blip in the availability
  # Separating addons to avoid errors such as
  # dial tcp 127.0.0.1:16443: connect: connection refused
  microk8s.enable dns
  microk8s.kubectl rollout status deployments/coredns -n kube-system -w --timeout=600s

  microk8s.enable rbac

  # wait for storage become available
  microk8s.enable hostpath-storage
  microk8s.kubectl rollout status deployments/hostpath-provisioner -n kube-system -w --timeout=600s

  # MetalLB
  microk8s enable metallb:{{IPADDR}}-{{IPADDR}}
  microk8s.kubectl rollout status daemonset.apps/speaker -n metallb-system -w --timeout=600s

  # Microk8s built-in registry
  microk8s enable registry
  microk8s.kubectl rollout status deployment.apps/registry -n container-registry -w --timeout=600s

  # Dump config (this is needed for utils such as k9s or kdash)
  sudo -u ${SUDO_USER:-$USER} mkdir -p /home/${SUDO_USER:-$USER}/.kube
  microk8s config | sudo -u ${SUDO_USER:-$USER} tee /home/${SUDO_USER:-$USER}/.kube/config > /dev/null


lxd:
  # Ref: https://github.com/canonical/setup-lxd/blob/main/action.yml
  lxd init --auto
  adduser ${SUDO_USER:-$USER} lxd


juju: lxd
  snap install juju --channel=3.6/stable

  # Make sure juju directory is there
  # https://bugs.launchpad.net/juju/+bug/1995697
  sudo -u ${SUDO_USER:-$USER} mkdir -p /home/${SUDO_USER:-$USER}/.local/share/juju

  snap install jhack --channel=latest/stable
  sudo snap connect jhack:dot-local-share-juju snapd
  sudo snap connect jhack:ssh-read snapd


starcraft: lxd
  snap install --classic charmcraft
  apt install -y gnome-keyring

  snap install --classic rockcraft
  snap install --classic snapcraft


default-models:
  sudo -u ${SUDO_USER:-$USER} juju controllers --format=json | jq -r '.controllers | keys .[]' | grep -q '^lxd$' || sudo -u ${SUDO_USER:-$USER} juju bootstrap localhost lxd
  sudo -u ${SUDO_USER:-$USER} juju models --controller lxd --format=json | jq -r '.models | .[].name' | grep -q '^admin/welcome-lxd$' || sudo -u ${SUDO_USER:-$USER} juju add-model --controller lxd --config logging-config="<root>=WARNING; unit=DEBUG" --config update-status-hook-interval="60m" welcome-lxd
  sudo -u ${SUDO_USER:-$USER} juju controllers --format=json | jq -r '.controllers | keys .[]' | grep -q '^microk8s$' || sudo -u ${SUDO_USER:-$USER} juju bootstrap microk8s microk8s
  sudo -u ${SUDO_USER:-$USER} juju models --controller microk8s --format=json | jq -r '.models | .[].name' | grep -q '^admin/welcome-k8s$' || sudo -u ${SUDO_USER:-$USER} juju add-model --controller microk8s --config logging-config="<root>=WARNING; unit=DEBUG" --config update-status-hook-interval="60m" welcome-k8s


oh-my-zsh:
  sudo -u ${SUDO_USER:-$USER} sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  sudo -u ${SUDO_USER:-$USER} git clone https://github.com/zsh-users/zsh-autosuggestions.git ~${SUDO_USER:-$USER}/.oh-my-zsh/custom/plugins/zsh-autosuggestions
  sudo -u ${SUDO_USER:-$USER} git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~${SUDO_USER:-$USER}/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
  sudo -u ${SUDO_USER:-$USER} sed -i 's/plugins=(git)/plugins=(fzf git zsh-autosuggestions zsh-syntax-highlighting virtualenv colored-man-pages juju colorize)/g' ~${SUDO_USER:-$USER}/.zshrc


nu:
  snap install nushell --classic


microceph:
  # Ref: https://canonical-microceph.readthedocs-hosted.com/en/latest/tutorial/get-started/
  sudo snap install microceph
  sudo snap refresh --hold microceph
  sudo microceph cluster bootstrap
  sudo microceph disk add loop,4G,3
  sudo ceph status

  # Ref: https://canonical-microceph.readthedocs-hosted.com/en/latest/reference/commands/enable/#rgw
  # (Traefik will take ports 80, 443)
  sudo microceph enable rgw --port 8080 --ssl-port 8443
  sudo microceph.ceph -s
  sudo microceph.radosgw-admin user create --uid=user --display-name=User
  sudo microceph.radosgw-admin key create --uid=user --key-type=s3 --access-key=access-key --secret-key=secret-key

  sudo apt install -y s3cmd
  # Now you can create buckets with:
  # s3cmd --host=localhost:8080 --access_key=access-key --secret_key=secret-key --host-bucket= --no-ssl mb s3://loki


charm-dev: update init utils microk8s juju starcraft default-models && _banner


_cos_tf:
  #!/usr/bin/env sh
  dn=$(mktemp -d)
  echo "Workdir: $dn"
  fn="${dn}/cos.tf"
  cat << 'EOF' > $fn
  module "cos" {
    source                        = "git::https://github.com/canonical/observability//terraform/modules/cos"
    model_name                    = "cos"
    channel                       = "latest/edge"
    s3_endpoint                   = "http://{{IPADDR}}:8080"
    s3_password                   = "secret-key"
    s3_user                       = "user"
    loki_bucket                   = "loki"
    mimir_bucket                  = "mimir"
    tempo_bucket                  = "tempo"
    loki_backend_units            = 1
    loki_read_units               = 1
    loki_write_units              = 1
    mimir_backend_units           = 1
    mimir_read_units              = 1
    mimir_write_units             = 1
    tempo_compactor_units         = 1
    tempo_distributor_units       = 1
    tempo_ingester_units          = 1
    tempo_metrics_generator_units = 1
    tempo_querier_units           = 1
    tempo_query_frontend_units    = 1
    cloud                         = "self-managed"
    ssc_channel                   = "latest/edge"
  }
  EOF
  terraform -chdir=$dn init
  terraform -chdir=$dn apply -auto-approve


terraform:
  sudo snap install terraform --classic


cos: terraform && _cos_tf
  s3cmd --host=localhost:80 --access_key=access-key --secret_key=secret-key --host-bucket= --no-ssl mb s3://loki
  s3cmd --host=localhost:80 --access_key=access-key --secret_key=secret-key --host-bucket= --no-ssl mb s3://mimir
  s3cmd --host=localhost:80 --access_key=access-key --secret_key=secret-key --host-bucket= --no-ssl mb s3://tempo

  juju add-model cos
