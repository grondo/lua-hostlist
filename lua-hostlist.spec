Name:		
Version:	
Release:	1%{?dist}
Summary:	Lua hostlist library

Group:		Development/Libraries
License:	GPL
URL:		http://code.google.com/p/lua-hostlist
Source0:	
BuildRoot:	%(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

BuildRequires:	lua-devel >= 5.1
Requires:	    lua >= 5.1

%description
This package implements a Lua interface to the LLNL hostlist routines,
and includes a hostlist command line utility based on the lua hostlist
library.


%prep
%setup -q


%build
make %{?_smp_mflags}
make check


%install
rm -rf $RPM_BUILD_ROOT
make install \
    DESTDIR=$RPM_BUILD_ROOT \
	PREFIX=%{_prefix} \
	LIBDIR=%{_libdir} \
	LUA_VER=$(lua -e 'print (string.match (_VERSION, "Lua ([%d.]+)"))')


%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%{_bindir}/hostlist
%{_libdir}/*/*



%changelog

