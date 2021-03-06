#!/usr/bin/env bash

if [[ $(whoami) != 'root' ]]; then
    echo "This script must run under root!"
    exit 1
fi

if [[ "$(grep -Ei 'centos|fedora' /etc/*release)" ]]; then
    serviceUser="nginx"
else
    serviceUser="www-data"
fi

# get sure that we have our correct PATH
export PATH=$PATH:/usr/local/bin
export NUXT_TELEMETRY_DISABLED=1

runInstall() {
    if [[ ! -f "/etc/ffplayout/ffplayout.yml" ]]; then
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "path to media storage, default: /opt/ffplayout/media"
        echo "------------------------------------------------------------------------------"
        echo ""

        read -p "media path :$ " mediaPath

        if [[ -z "$mediaPath" ]]; then
            mediaPath="/opt/ffplayout/media"
        fi

        echo ""
        echo "------------------------------------------------------------------------------"
        echo "playlist path, default: /opt/ffplayout/playlists"
        echo "------------------------------------------------------------------------------"
        echo ""

        read -p "playlist path :$ " playlistPath

        if [[ -z "$playlistPath" ]]; then
            playlistPath="/opt/ffplayout/playlists"
        fi
    fi

    if ! ffmpeg -version &> /dev/null; then
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "compile and install (nonfree) ffmpeg:"
        echo "------------------------------------------------------------------------------"
        echo ""
        while true; do
            read -p "Do you wish to compile ffmpeg? (Y/n) :$ " yn
            case $yn in
                [Yy]* ) compileFFmpeg="y"; break;;
                [Nn]* ) compileFFmpeg="n"; break;;
                * ) (
                    echo "------------------------------------"
                    echo "Please answer yes or no!"
                    echo ""
                    );;
            esac
        done
    fi

    if ! nginx -t &> /dev/null; then
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "install and setup nginx:"
        echo "------------------------------------------------------------------------------"
        echo ""
        while true; do
            read -p "Do you wish to install nginx? (Y/n) :$ " yn
            case $yn in
                [Yy]* ) installNginx="y"; break;;
                [Nn]* ) installNginx="n"; break;;
                * ) (
                    echo "------------------------------------"
                    echo "Please answer yes or no!"
                    echo ""
                    );;
            esac
        done

        echo ""
        echo "------------------------------------------------------------------------------"
        echo "ffplayout domain name (like: example.org)"
        echo "------------------------------------------------------------------------------"
        echo ""

        read -p "domain name :$ " domainFrontend
    fi

    if [[ ! -d /usr/local/srs ]]; then
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "install and srs rtmp/hls server:"
        echo "------------------------------------------------------------------------------"
        echo ""
        while true; do
            read -p "Do you wish to install srs? (Y/n) :$ " yn
            case $yn in
                [Yy]* ) installSRS="y"; break;;
                [Nn]* ) installSRS="n"; break;;
                * ) (
                    echo "------------------------------------"
                    echo "Please answer yes or no!"
                    echo ""
                    );;
            esac
        done
    fi

    if [[ ! -d "/opt/ffplayout-engine" ]]; then
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "install ffplayout-engine:"
        echo "------------------------------------------------------------------------------"
        echo ""
        while true; do
            read -p "Do you wish to install ffplayout-engine? (Y/n) :$ " yn
            case $yn in
                [Yy]* ) installEngine="y"; break;;
                [Nn]* ) installEngine="n"; break;;
                * ) (
                    echo "------------------------------------"
                    echo "Please answer yes or no!"
                    echo ""
                    );;
            esac
        done
    fi

    echo ""
    echo "------------------------------------------------------------------------------"
    echo "install main packages"
    echo "------------------------------------------------------------------------------"

    if [[ "$(grep -Ei 'debian|buntu|mint' /etc/*release)" ]]; then
        packages=(sudo curl wget net-tools git python3-dev build-essential virtualenv
                  python3-virtualenv mediainfo autoconf automake libtool pkg-config
                  yasm cmake mercurial gperf)
        installedPackages=$(dpkg --get-selections | awk '{print $1}' | tr '\n' ' ')
        apt update

        if [[ "$installedPackages" != *"curl"* ]]; then
            apt install -y curl
        fi

        if [[ "$installedPackages" != *"nodejs"* ]]; then
            curl -sL https://deb.nodesource.com/setup_12.x | bash -
            apt install -y nodejs
        fi

        for pkg in ${packages[@]}; do
            if [[ "$installedPackages" != *"$pkg"* ]]; then
                apt install -y $pkg
            fi
        done

        if [[ $installNginx == 'y' ]] && [[ "$installedPackages" != *"nginx"* ]]; then
            apt install -y nginx
            rm /etc/nginx/sites-enabled/default
        fi

        nginxConfig="/etc/nginx/sites-available"

    elif [[ "$(grep -Ei 'centos|fedora' /etc/*release)" ]]; then
        packages=(libstdc++-static yasm mercurial libtool libmediainfo mediainfo
                  cmake net-tools git python3 python36-devel wget python3-virtualenv
                  gperf nano nodejs python3-policycoreutils policycoreutils-devel)
        installedPackages=$(dnf list --installed | awk '{print $1}' | tr '\n' ' ')
        activeRepos=$(dnf repolist enabled | awk '{print $1}' | tr '\n' ' ')

        if [[ "$activeRepos" != *"epel"* ]]; then
            dnf -y install epel-release
        fi

        if [[ "$activeRepos" != *"PowerTools"* ]]; then
            dnf -y config-manager --enable PowerTools
        fi

        if [[ "$activeRepos" != *"nodesource"* ]]; then
            curl -sL https://rpm.nodesource.com/setup_12.x | sudo -E bash -
        fi

        for pkg in ${packages[@]}; do
            if [[ "$installedPackages" != *"$pkg"* ]]; then
                dnf -y install $pkg
            fi
        done

        if [[ ! $(dnf group list  "Development Tools" | grep -i "install") ]]; then
            dnf -y group install "Development Tools"
        fi

        if [[ $installNginx == 'y' ]] && [[ "$installedPackages" != *"nginx"* ]]; then
            dnf -y install nginx
            systemctl enable nginx
            systemctl start nginx
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --zone=public --add-service=https
            firewall-cmd --reload
            mkdir /var/www
            chcon -vR system_u:object_r:httpd_sys_content_t:s0 /var/www
        fi

        if [[ $(alternatives --list | grep "no-python") ]]; then
            alternatives --set python /usr/bin/python3
        fi

        nginxConfig="/etc/nginx/conf.d"
    fi

    if [[ $compileFFmpeg == 'y' ]]; then
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "compile and install ffmpeg"
        echo "------------------------------------------------------------------------------"
        cd /opt/

        if [[ ! -d "ffmpeg-build" ]]; then
            git clone https://github.com/jb-alvarado/compile-ffmpeg-osx-linux.git ffmpeg-build
        fi

        cd ffmpeg-build

        if [[ ! -f "build_config.txt" ]]; then
cat <<EOF > "build_config.txt"
#--enable-decklink
--disable-ffplay
--disable-sdl2
--enable-fontconfig
#--enable-libaom
#--enable-libass
#--enable-libbluray
--enable-libfdk-aac
--enable-libfribidi
--enable-libfreetype
--enable-libmp3lame
--enable-libopus
--enable-libsoxr
#--enable-libsrt
--enable-libtwolame
--enable-libvpx
--enable-libx264
--enable-libx265
--enable-libzimg
--enable-libzmq
--enable-nonfree
#--enable-opencl
#--enable-opengl
#--enable-openssl
#--enable-libsvtav1
EOF
            sed -i 's/mediainfo="yes"/mediainfo="no"/g' ./compile-ffmpeg.sh
            sed -i 's/mp4box="yes"/mp4box="no"/g' ./compile-ffmpeg.sh
        fi

        ./compile-ffmpeg.sh

        \cp local/bin/ff* /usr/local/bin/
    fi

    if [[ $installSRS == 'y' ]] && [[ ! -d "/usr/local/srs" ]]; then
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "compile and install srs"
        echo "------------------------------------------------------------------------------"

        cd /opt/
        git clone https://github.com/ossrs/srs.git
        cd srs/trunk/

        ./configure
        make
        make install

        mkdir -p "/var/www/srs/live"
        mkdir "/etc/srs"

cat <<EOF > "/etc/srs/srs.conf"
listen              1935;
max_connections     20;
daemon              on;
pid                 /usr/local/srs/objs/srs.pid;
srs_log_tank        console; # file;
srs_log_file        /var/log/srs.log;
ff_log_dir          /tmp;

# can be: verbose, info, trace, warn, error
srs_log_level       error;

http_api {
    enabled         on;
    listen          1985;
}

stats {
    network         0;
    disk            sda vda xvda xvdb;
}

vhost __defaultVhost__ {
    # timestamp correction
    mix_correct     on;

    http_hooks {
        enabled         off;
        on_publish      http://127.0.0.1:8085/api/v1/streams;
        on_unpublish    http://127.0.0.1:8085/api/v1/streams;
    }

    hls {
        enabled         on;
        hls_path        /var/www/srs;
        hls_fragment    6;
        hls_window      3600;
        hls_cleanup     on;
        hls_dispose     0;
        hls_m3u8_file   live/stream.m3u8;
        hls_ts_file     live/stream-[seq].ts;
    }
}
EOF

cat <<EOF > "/etc/systemd/system/srs.service"
[Unit]
Description=SRS
Documentation=https://github.com/ossrs/srs/wiki
After=network.target

[Service]
Type=forking
ExecStartPre=/usr/local/srs/objs/srs -t -c /etc/srs/srs.conf
ExecStart=/usr/local/srs/objs/srs -c /etc/srs/srs.conf
ExecStop=/bin/kill -TERM \$MAINPID
ExecReload=/bin/kill -1 \$MAINPID
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

        systemctl enable srs.service
        systemctl start srs.service
    fi

    if [[ "$(grep -Ei 'centos|fedora' /etc/*release)" ]]; then
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "creating selinux rules"
        echo "------------------------------------------------------------------------------"

        if [[ $(getsebool httpd_can_network_connect | awk '{print $NF}') == "off" ]]; then
            setsebool httpd_can_network_connect on -P
        fi

        if [[ ! $(semanage port -l | grep http_port_t | grep "8001") ]]; then
            semanage port -a -t http_port_t -p tcp 8001
        fi

        if [[ ! $(semodule -l | grep gunicorn) ]]; then
cat <<EOF > gunicorn.te
module gunicorn 1.0;

require {
    type init_t;
    type httpd_sys_content_t;
    type unreserved_port_t;
	class tcp_socket name_connect;
    type etc_t;
    type sudo_exec_t;
    class file { create execute execute_no_trans getattr ioctl lock map open read unlink write };
    class lnk_file { getattr read };
}

#============= init_t ==============

#!!!! This avc is allowed in the current policy
allow init_t etc_t:file write;

#!!!! This avc is allowed in the current policy
#!!!! This av rule may have been overridden by an extended permission av rule
allow init_t httpd_sys_content_t:file { create execute execute_no_trans getattr ioctl lock map open read unlink write };

#!!!! This avc is allowed in the current policy
allow init_t httpd_sys_content_t:lnk_file { getattr read };

#!!!! This avc can be allowed using the boolean 'nis_enabled'
allow init_t unreserved_port_t:tcp_socket name_connect;

#!!!! This avc is allowed in the current policy
allow init_t sudo_exec_t:file { execute execute_no_trans map open read };
EOF

            checkmodule -M -m -o gunicorn.mod gunicorn.te
            semodule_package -o gunicorn.pp -m gunicorn.mod
            semodule -i gunicorn.pp

            rm -f gunicorn.*
        fi

        if [[ ! $(semodule -l | grep "custom-http") ]]; then
cat <<EOF > custom-http.te
module custom-http 1.0;

require {
    type init_t;
    type httpd_sys_content_t;
    class file { create lock unlink write };
}

#============= init_t ==============
allow init_t httpd_sys_content_t:file unlink;

#!!!! This avc is allowed in the current policy
allow init_t httpd_sys_content_t:file { create lock write };
EOF

            checkmodule -M -m -o custom-http.mod custom-http.te
            semodule_package -o custom-http.pp -m custom-http.mod
            semodule -i custom-http.pp

            rm -f custom-http.*
        fi

        if [[ ! $(semodule -l | grep "custom-fileop") ]]; then
cat <<EOF > custom-fileop.te
module custom-fileop 1.0;

require {
    type init_t;
    type httpd_sys_content_t;
    type usr_t;
    class file { create rename unlink write };
    class dir { create rmdir };
}

#============= init_t ==============
allow init_t httpd_sys_content_t:file rename;

#!!!! This avc is allowed in the current policy
allow init_t usr_t:dir create;
allow init_t usr_t:dir rmdir;

#!!!! This avc is allowed in the current policy
allow init_t usr_t:file create;
allow init_t usr_t:file { rename unlink write };

EOF

            checkmodule -M -m -o custom-fileop.mod custom-fileop.te
            semodule_package -o custom-fileop.pp -m custom-fileop.mod
            semodule -i custom-fileop.pp

            rm -f custom-fileop.*
        fi
    fi

    if ! grep -q "ffplayout-engine.service" "/etc/sudoers"; then
      echo "$serviceUser  ALL = NOPASSWD: /bin/systemctl start ffplayout-engine.service, /bin/systemctl stop ffplayout-engine.service, /bin/systemctl reload ffplayout-engine.service, /bin/systemctl restart ffplayout-engine.service, /bin/systemctl status ffplayout-engine.service, /bin/systemctl is-active ffplayout-engine.service, /bin/journalctl -n 1000 -u ffplayout-engine.service" >> /etc/sudoers
    fi

    if [[ "$installEngine" == "y" ]] && [[ ! -d "/opt/ffplayout-engine" ]]; then
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "install ffplayout engine"
        echo "------------------------------------------------------------------------------"

        cd /opt
        git clone https://github.com/Dreamsee-FR/ffplayout-engine.git
        cd ffplayout-engine

        virtualenv -p python3 venv
        source ./venv/bin/activate

        pip install -r requirements-base.txt

        mkdir /etc/ffplayout
        mkdir /var/log/ffplayout
        mkdir -p $mediaPath
        mkdir -p $playlistPath

        cp ffplayout.yml /etc/ffplayout/
        chown -R $serviceUser. /etc/ffplayout
        chown $serviceUser. /var/log/ffplayout
        chown $serviceUser. $mediaPath
        chown $serviceUser. $playlistPath

        cp docs/ffplayout-engine.service /etc/systemd/system/
        sed -i "s/User=root/User=$serviceUser/g" /etc/systemd/system/ffplayout-engine.service
        sed -i "s/Group=root/Group=$serviceUser/g" /etc/systemd/system/ffplayout-engine.service

        sed -i "s|\"\/playlists\"|\"$playlistPath\"|g" /etc/ffplayout/ffplayout.yml
        sed -i "s|\"\/mediaStorage|\"$mediaPath|g" /etc/ffplayout/ffplayout.yml

        systemctl enable ffplayout-engine.service

        deactivate
    fi

    if [[ ! -d "/var/www/ffplayout-api" ]]; then
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "install ffplayout-api"
        echo "------------------------------------------------------------------------------"

        cd /var/www
        git clone https://github.com/Dreamsee-FR/ffplayout-api.git
        cd ffplayout-api

        virtualenv -p python3 venv
        source ./venv/bin/activate

        pip install -r requirements-base.txt

        cd ffplayout

        secret=$(python manage.py shell -c 'from django.core.management import utils; print(utils.get_random_secret_key())')

        sed -i "s/---a-very-important-secret-key\:-generate-it-new---/$secret/g" ffplayout/settings/production.py
        sed -i "s/localhost/$domainFrontend/g" ../docs/db_data.json

        python manage.py makemigrations && python manage.py migrate
        python manage.py collectstatic
        python manage.py loaddata ../docs/db_data.json
        python manage.py createsuperuser

        deactivate

        chown $serviceUser. -R /var/www

        cd ..

        cp docs/ffplayout-api.service /etc/systemd/system/

        sed -i "s/User=root/User=$serviceUser/g" /etc/systemd/system/ffplayout-api.service
        sed -i "s/Group=root/Group=$serviceUser/g" /etc/systemd/system/ffplayout-api.service

        sed -i "s/'localhost'/'localhost', \'$domainFrontend\'/g" /var/www/ffplayout-api/ffplayout/ffplayout/settings/production.py
        sed -i "s/ffplayout\\.local/$domainFrontend\'\n    \'https\\:\/\/$domainFrontend/g" /var/www/ffplayout-api/ffplayout/ffplayout/settings/production.py

        systemctl enable ffplayout-api.service
        systemctl start ffplayout-api.service
    fi

    if [[ ! -d "/var/www/ffplayout-frontend" ]]; then
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "install ffplayout-frontend"
        echo "------------------------------------------------------------------------------"

        cd /var/www
        git clone https://github.com/Dreamsee-FR/ffplayout-frontend.git
        cd ffplayout-frontend

        ln -s "$mediaPath" /var/www/ffplayout-frontend/static/

        npm install

cat <<EOF > ".env"
BASE_URL='http://$domainFrontend'
API_URL='/'
EOF

        npm run build

        chown $serviceUser. -R /var/www

        if [[ $installNginx == 'y' ]]; then
            cp docs/ffplayout.conf "$nginxConfig/"

            origin=$(echo "$domainFrontend" | sed 's/\./\\\\./g')

            sed -i "s/ffplayout.local/$domainFrontend/g" $nginxConfig/ffplayout.conf
            sed -i "s/ffplayout\\\.local/$origin/g" $nginxConfig/ffplayout.conf

            if [[ "$(grep -Ei 'debian|buntu|mint' /etc/*release)" ]]; then
                ln -s $nginxConfig/ffplayout.conf /etc/nginx/sites-enabled/
            fi
        fi
    fi

    if [[ $installNginx == 'y' ]]; then
        systemctl restart nginx
    fi

    echo ""
    echo "------------------------------------------------------------------------------"
    echo "installation done..."
    echo "------------------------------------------------------------------------------"

    echo ""
    echo "add your ssl config to $nginxConfig/ffplayout.conf"
    echo ""
}

runUpdate() {
    if [[ -d "/opt/ffmpeg-build" ]]; then
        cd "/opt/ffmpeg-build"

        git pull

        ./compile-ffmpeg.sh

        echo ""
        echo "------------------------------------------------------------------------------"
        echo "updating ffmpeg-build done..."
        echo "------------------------------------------------------------------------------"
    fi

    if [[ -d "/opt/ffplayout-engine" ]]; then
        cd "/opt/ffplayout-engine"
        git pull

        source ./venv/bin/activate
        pip install --upgrade -r requirements-base.txt
        deactivate

        echo ""
        echo "------------------------------------------------------------------------------"
        echo "updating ffplayout-engine done..."
        echo "------------------------------------------------------------------------------"
    else
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "WARNING: no ffplayout-engine found..."
        echo "------------------------------------------------------------------------------"
    fi

    if [[ -d "/var/www/ffplayout-api" ]]; then
        cd "/var/www/ffplayout-api"
        git pull

        source ./venv/bin/activate
        pip install --upgrade -r requirements-base.txt
        deactivate

        echo ""
        echo "------------------------------------------------------------------------------"
        echo "updating ffplayout-api done..."
        echo "------------------------------------------------------------------------------"
    else
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "WARNING: no ffplayout-api found..."
        echo "------------------------------------------------------------------------------"
    fi

    if [[ -d "/var/www/ffplayout-frontend" ]]; then
        cd "/var/www/ffplayout-frontend"
        git pull

        rm -rf node_modules
        sudo -H -u $serviceUser bash -c 'npm install'
        sudo -H -u $serviceUser bash -c 'npm run build'

        echo ""
        echo "------------------------------------------------------------------------------"
        echo "updating ffplayout-frontend done..."
        echo "------------------------------------------------------------------------------"
    else
        echo ""
        echo "------------------------------------------------------------------------------"
        echo "WARNING: no ffplayout-frontend found..."
        echo "------------------------------------------------------------------------------"
    fi

    echo ""
    echo "------------------------------------------------------------------------------"
    echo "updating done..."
    echo "if there is a new ffmpeg version, run:"
    echo "    systemctl stop ffplayout-engine"
    echo "    cp /opt/ffmpeg-build/local/bin/ff* /usrlocal/bin"
    echo "    systemctl start ffplayout-engine"
    echo ""
    echo "to apply update restart services:"
    echo "    systemctl restart ffplayout-engine"
    echo "    systemctl restart ffplayout-api"
}

if [[ "$1" == "update" ]]; then
    runUpdate
else
    runInstall
fi
