Name:       fingerbank
Version:    3.0.1
Release:    1%{?dist}
BuildArch:  noarch
Summary:    An exhaustive device profiling tool
Packager:   Inverse inc. <info@inverse.ca>
Group:      System Environment/Daemons
License:    GPL
URL:        http://www.fingerbank.org/

Source0:    https://support.inverse.ca/~dwuelfrath/fingerbank.tar.gz

BuildRoot:  %{_tmppath}/%{name}-root

Requires(post):     /sbin/chkconfig
Requires(preun):    /sbin/chkconfig

Requires(pre):      /usr/sbin/useradd, /usr/sbin/groupadd, /usr/bin/getent
Requires(postun):   /usr/sbin/userdel

Requires:   perl
Requires:   perl-version
Requires:   perl(Catalyst::Runtime)
Requires:   perl(aliased)
Requires:   perl(MooseX::Types::LoadableClass)
Requires:   perl(Catalyst::Plugin::Static::Simple)
Requires:   perl(Catalyst::Plugin::ConfigLoader)
Requires:   perl(Config::General)
Requires:   perl(Readonly)
Requires:   perl(Log::Log4perl)
Requires:   perl(Catalyst::Model::DBIC::Schema)
Requires:   perl(Catalyst::Action::REST)
Requires:   perl(DBD::SQLite)
Requires:   perl(LWP::Protocol::https)
Requires:   perl(MooseX::NonMoose)
Requires:   perl(SQL::Translator)
Requires:   perl(File::Touch)

%description
Fingerbank


%pre
/usr/bin/getent group fingerbank || /usr/sbin/groupadd -r fingerbank
/usr/bin/getent passwd fingerbank || /usr/sbin/useradd -r -d /usr/local/fingerbank -s /sbin/nologin -g fingerbank fingerbank


%prep
%setup -q


%build


%install
# /usr/local/fingerbank
rm -rf %{buildroot}
%{__install} -d $RPM_BUILD_ROOT/usr/local/fingerbank
cp -r * $RPM_BUILD_ROOT/usr/local/fingerbank
touch $RPM_BUILD_ROOT/usr/local/fingerbank/logs/fingerbank.log

# Logrotate
%{__install} -D rhel/fingerbank.logrotate $RPM_BUILD_ROOT/etc/logrotate.d/fingerbank


%post
# Local database initialization
cd /usr/local/fingerbank/
make init-db-local

# Log file handling
if [ ! -e /usr/local/fingerbank/logs/fingerbank.log ]; then
    touch /usr/local/fingerbank/logs/fingerbank.log
fi

# fingerbank.conf empty file handling
if [ ! -f /usr/local/fingerbank/conf/fingerbank.conf ]; then
    echo "Creating non-existing 'fingerbank.conf' file"
    touch /usr/local/fingerbank/conf/fingerbank.conf
fi

# applying / fixing permissions
make fixpermissions

%clean
rm -rf %{buildroot}


%postun


%files
%defattr(664,fingerbank,fingerbank,2775)
%dir                                /usr/local/fingerbank
                                    /usr/local/fingerbank/*
%attr(775,fingerbank,fingerbank)    /usr/local/fingerbank/db/upgrade.pl
%if 0%{?el6}
    %dir                            %{_sysconfdir}/logrotate.d
%endif
%config %attr(0644,root,root)       %{_sysconfdir}/logrotate.d/fingerbank
%ghost                              /usr/local/fingerbank/logs/fingerbank.log
%attr(664,fingerbank,fingerbank)    /usr/local/fingerbank/logs/fingerbank.log


%changelog
