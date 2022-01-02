#!/bin/bash

machine=""
cloudreve_version="3.3.1"
cloudreve_prefix="/usr/local/cloudreve"
cloudreve_service="/etc/systemd/system/cloudreve.service"
cloudreve_is_installed=""
nginx_prefix="/etc/nginx/conf/conf.d"

#定义几个颜色
purple()                           #基佬紫
{
    echo -e "\\033[35;1m${*}\\033[0m"
}
tyblue()                           #天依蓝
{
    echo -e "\\033[36;1m${*}\\033[0m"
}
green()                            #原谅绿
{
    echo -e "\\033[32;1m${*}\\033[0m"
}
yellow()                           #鸭屎黄
{
    echo -e "\\033[33;1m${*}\\033[0m"
}
red()                              #姨妈红
{
    echo -e "\\033[31;1m${*}\\033[0m"
}
blue()                             #蓝色
{
    echo -e "\\033[34;1m${*}\\033[0m"
}

case "$(uname -m)" in
    'amd64' | 'x86_64')
        machine='amd64'
        ;;
    'armv5tel' | 'armv6l' | 'armv7' | 'armv7l')
        machine='arm'
        ;;
    'armv8' | 'aarch64')
        machine='arm64'
        ;;
    *)
        machine=''
        ;;
esac

#启用/禁用 cloudreve

turn_on_off_cloudreve()
{
    if check_need_cloudreve; then
        systemctl start cloudreve
        systemctl enable cloudreve
    else
        systemctl stop cloudreve
        systemctl disable cloudreve
    fi
}

#初始化 cloudreve
init_cloudreve()
{
    local temp
    temp="$(timeout 5s $cloudreve_prefix/cloudreve | grep "初始管理员密码：" | awk '{print $4}')"
    sleep 1s
    systemctl start cloudreve
    systemctl enable cloudreve
    tyblue "-------- 请打开\"https://${domain_list[$1]}\"进行Cloudreve初始化 -------"
    tyblue "  1. 登陆帐号"
    purple "    初始管理员账号：admin@cloudreve.org"
    purple "    $temp"
    tyblue "  2. 右上角头像 -> 管理面板"
    tyblue "  3. 这时会弹出对话框 \"确定站点URL设置\" 选择 \"更改\""
    tyblue "  4. 左侧参数设置 -> 注册与登陆 -> 不允许新用户注册 -> 往下拉点击保存"
    sleep 15s
    echo -e "\\n\\n"
    tyblue "按两次回车键以继续。。。"
    read -s
    read -s
}

#移除 cloudreve
remove_cloudreve()
{
    systemctl stop cloudreve
    systemctl disable cloudreve
    rm -rf $cloudreve_service
    systemctl daemon-reload
    rm -rf ${cloudreve_prefix}
    cloudreve_is_installed=0
}

#修改Nginx 配置,需手工配置
init_nginx()
{
cat >> $nginx_config<<EOF
    location / {
        proxy_redirect off;
        proxy_pass http://unix:/dev/shm/cloudreve_unixsocket/cloudreve.sock;
        client_max_body_size 0;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }
EOF
}

#安装/更新Cloudreve
update_cloudreve()
{
    if ! wget -O cloudreve.tar.gz "https://github.com/cloudreve/Cloudreve/releases/download/${cloudreve_version}/cloudreve_${cloudreve_version}_linux_${machine}.tar.gz"; then
        red "获取Cloudreve失败！！"
        yellow "按回车键继续或者按Ctrl+c终止"
        read -s
    fi
    tar -zxf cloudreve.tar.gz
    local temp_cloudreve_status=0
    systemctl -q is-active cloudreve && temp_cloudreve_status=1
    systemctl stop cloudreve
    cp cloudreve $cloudreve_prefix
    
    cat > $cloudreve_prefix/conf.ini << EOF
[System]
Mode = master
Debug = false
[UnixSocket]
Listen = /dev/shm/cloudreve_unixsocket/cloudreve.sock
EOF
    
    rm -rf $cloudreve_service  
    cat > $cloudreve_service << EOF
[Unit]
Description=Cloudreve
Documentation=https://docs.cloudreve.org
After=network.target
After=mysqld.service
Wants=network.target

[Service]
WorkingDirectory=$cloudreve_prefix
ExecStartPre=/bin/rm -rf /dev/shm/cloudreve_unixsocket
ExecStartPre=/bin/mkdir /dev/shm/cloudreve_unixsocket
ExecStartPre=/bin/chmod 711 /dev/shm/cloudreve_unixsocket
ExecStart=$cloudreve_prefix/cloudreve
ExecStopPost=/bin/rm -rf /dev/shm/cloudreve_unixsocket
Restart=on-abnormal
RestartSec=5s
KillMode=mixed

StandardOutput=null
StandardError=syslog

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    [ $temp_cloudreve_status -eq 1 ] && systemctl start cloudreve
}

#安装并初始化 Cloudreve
install_init_cloudreve()
{
    remove_cloudreve
    mkdir -p $cloudreve_prefix
    update_cloudreve
    init_cloudreve "$1"
    cloudreve_is_installed=1
}

#重置 Cloudreve
reinit_cloudreve()
{
    ! check_need_cloudreve && red "Cloudreve目前没有绑定域名" && return 1
    red "重置Cloudreve将删除所有的Cloudreve网盘文件以及帐户信息，相当于重新安装"
    tyblue "管理员密码忘记可以用此选项恢复"
    ! ask_if "确定要继续吗？(y/n)" && return 0
    local i
    for i in ${!pretend_list[@]}
    do
        [ "${pretend_list[$i]}" == "1" ] && break
    done
    systemctl stop cloudreve
    enter_temp_dir
    mv "$cloudreve_prefix/cloudreve" "$temp_dir"
    mv "$cloudreve_prefix/conf.ini" "$temp_dir"
    rm -rf "$cloudreve_prefix"
    mkdir -p "$cloudreve_prefix"
    mv "$temp_dir/cloudreve" "$cloudreve_prefix"
    mv "$temp_dir/conf.ini" "$cloudreve_prefix"
    init_cloudreve "$i"
    cd /
    rm -rf "$temp_dir"
    green "重置完成！"
}

start_menu()
{
    purple "   1. 安装cloudreve"
    green  "   2. 删除cloudreve"
    purple "   3. 重置cloudreve"
    yellow "   4. 更新cloudreve"
    red    "   5. 重启cloudreve"
    echo
    echo
    local choice=""
    while [[ ! "$choice" =~ ^(0|[1-9][0-9]*)$ ]] || ((choice>27))
    do
        read -p "您的选择是：" choice
    done

    if [ $choice -eq 1 ]; then
        install_init_cloudreve
    elif [ $choice -eq 2 ]; then
     	remove_cloudreve
    elif [ $choice -eq 3 ]; then
     	reinit_cloudreve
    elif [ $choice -eq 4 ]; then
     	update_cloudreve 
    elif [ $choice -eq 5 ]; then
        systemctl stop cloudreve
        systemctl disable cloudreve
     	systemctl start cloudreve
        systemctl enable cloudreve
    fi
}

start_menu

