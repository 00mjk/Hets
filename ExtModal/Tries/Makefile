# $Id$

.PHONY: check

check: hets
	../../hets -v2 -o pp.dol,th Try?.dol
	../../hets -v2 -o pp.dol,th Try?.pp.dol

%:
	(cd ../..; $(MAKE) $@)
