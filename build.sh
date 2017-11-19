#!/bin/bash

#Clean up old nginx builds
sudo rm -rf ~/rpmbuild/RPMS/*/nginx-*.rpm

#Install required packages for building
sudo yum groupinstall -y 'Development tools'
sudo yum install -y \
    rpm-build \
    rpmdevtools \
    yum-utils \
    mercurial \
    git \
    wget


#Install source RPM for Nginx
pushd ~
echo """[nginx-source]
name=nginx repo
baseurl=http://nginx.org/packages/mainline/centos/6/SRPMS/
gpgcheck=0
enabled=1""" > nginx.repo
sudo mv nginx.repo /etc/yum.repos.d/
rm -rf nginx*.src.rpm
yumdownloader --source nginx

if ! [ $? -eq 0 ]; then
    echo "Couldn't download Nginx source RPM. Aborting build."
    exit 1
fi

rpm -ihv nginx*.src.rpm
popd


#Get various add-on modules for Nginx
#XXX git clone -b [tag] isn't supported on git 1.7 (RHEL 6)
pushd ~/rpmbuild/SOURCES

    #Headers More module
    git clone https://github.com/openresty/headers-more-nginx-module
    pushd headers-more-nginx-module
    git checkout v0.29
    popd

    #Fancy Index module
    git clone https://github.com/aperezdc/ngx-fancyindex.git
    pushd ngx-fancyindex
    git checkout 80db501
    popd

    # Nginx Cache Purge
    git clone https://github.com/FRiCKLE/ngx_cache_purge.git
    tar cz ngx_cache_purge >ngx_cache_purge.tar.gz
    
    # Misc Fixes
    pushd ~/rpmbuild/SOURCES
        wget https://raw.githubusercontent.com/karlgray/nginx-pagespeed-modsecurity/master/nginx.vh.example_ssl.conf
    mv nginx.init.in nginx.init
    popd
    C_INCLUDE_PATH=/usr/include/httpd/
    export C_INCLUDE_PATH
    
popd

# Obtain a location for the patches, either from /vagrant
# or cloned from GitHub (if run stand-alone).
if [ -d '/vagrant' ]; then
    patch_dir='/vagrant'
else
    patch_dir=$(mktemp -d)
    git clone https://github.com/jcu-eresearch/nginx-custom-build.git "$patch_dir"
fi
cp "$patch_dir/nginx-eresearch.patch" ~/rpmbuild/SPECS/
cp "$patch_dir/nginx-xslt-html-parser.patch" ~/rpmbuild/SOURCES/
# Remove temp directory 
rm -rf "$patch_dir"


#Prep and patch the Nginx specfile for the RPMs
pushd ~/rpmbuild/SPECS
mv nginx.spec nginx.spec.orig
wget https://raw.githubusercontent.com/karlgray/nginx-rpm/nginx.spec
rpmbuild -ba nginx.spec

if ! [ $? -eq 0 ]; then
    echo "RPM build failed. See the output above to establish why."
    exit 1
fi

#Test installation and check output
sudo yum remove -y nginx nginx-debug
sudo yum install -y ~/rpmbuild/RPMS/*/nginx-*.rpm
nginx -V
