DESTDIR=
INSTALLDIR=/usr/lib/oscar/testing/unit_testing/etc

SUBDIRS := 
FILES := yum.conf

all:
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} all ) ; done

install:
	install -d -m 0755 $(DESTDIR)$(INSTALLDIR)
	install    -m 0755 ${FILES} $(DESTDIR)$(INSTALLDIR)
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} install ) ; done

uninstall:
	cd $(DESTDIR)$(INSTALLDIR) ; rm -f ${FILES}
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} uninstall ) ; done

clean:
	rm -f *~
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} clean ) ; done

