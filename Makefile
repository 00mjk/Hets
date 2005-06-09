# Makefile
# $Header$
# Author: (c) Klaus L�ttich, Christian Maeder, Uni Bremen 2002-2005
# Year:   2004

# This Makefile will compile the new hets system and provides also
# targets for test programs during implementation phases.

# !!! Note: This makefile is written for GNU make !!!
#           (gmake on solaris)

all: patch hets

####################################################################
## Some varibles, which control the compilation

INCLUDE_PATH = fgl hxt
COMMONLIB_PATH = Common/Lib Common/ATerm fgl/Data/Graph \
    fgl/Data/Graph/Inductive fgl/Data/Graph/Inductive/Internal \
    fgl/Data/Graph/Inductive/Monad fgl/Data/Graph/Inductive/Query
CLEAN_PATH = . utils/DrIFT-src utils/GenerateRules utils/InlineAxioms Common \
    Logic CASL CASL/CCC Syntax Static GUI HasCASL Haskell Modal CoCASL COL \
    CspCASL ATC ToHaskell Proofs Comorphisms Isabelle Driver $(INCLUDE_PATH) \
    Taxonomy CASL_DL SPASS $(PFE_PATHS)

# the 'replacing spaces' example was taken from the (GNU) Make info manual 
empty = 
space = $(empty) $(empty)

## set ghc imports properly for your system
GHC_IMPORTS = `$(HC) --print-libdir`/imports
# import directories for ghc-5.04.2
GHC5 = $(GHC_IMPORTS)/base:$(GHC_IMPORTS)/haskell98
DRIFT_ENV = \
    DERIVEPATH=.:ghc:$(GHC_IMPORTS):$(GHC5):$(subst $(space),:,$(PFE_PATHS))

# override on commandline for other architectures
INSTALLDIR = \
    /home/www/agbkb/forschung/formal_methods/CoFI/hets/`utils/sysname.sh`

DRIFT_deps = utils/DrIFT-src/*hs
GENERATERULES_deps = utils/GenerateRules/*hs $(DRIFT_deps) Common/Utils.hs
INLINEAXIOMS_deps = utils/InlineAxioms/InlineAxioms.hs \
    Common/Lib/Pretty.hs Common/Keywords.hs Common/Lib/Set.hs \
    Common/Lib/Map.hs Common/Lib/Rel.hs Common/Lib/State.hs Common/Id.hs \
    Common/AS_Annotation.hs CASL/AS_Basic_CASL.hs CASL/ShowMixfix.hs \
    CASL/Utils.hs Common/Lexer.hs Common/Token.hs Common/Anno_Parser.hs \
    Common/GlobalAnnotations.hs Common/PrettyPrint.hs \
    Common/Print_AS_Annotation.hs Common/PPUtils.hs CASL/LiteralFuns.hs \
    CASL/Print_AS_Basic.hs Common/AnnoState.hs CASL/Formula.hs \
    CASL/OpItem.hs CASL/SortItem.hs CASL/Inject.hs Common/Result.hs \
    Common/ConvertLiteral.hs Common/Earley.hs CASL/MixfixParser.hs \
    CASL/Parse_AS_Basic.hs CASL/Sign.hs CASL/Overload.hs \
    CASL/StaticAna.hs Modal/AS_Modal.hs Modal/Parse_AS.hs \
    Modal/ModalSign.hs Modal/Print_AS.hs Modal/StatAna.hs

HC = ghc
PERL = perl
HAPPY = happy -sga
DRIFT = utils/DrIFT
INLINEAXIOMS = utils/outlineAxioms
HADDOCK = haddock
CPPP = cpp 

# remove -fno-warn-orphans for older ghcs
HC_WARN = -Wall -fno-warn-orphans
HC_FLAGS = $(HC_WARN) -fglasgow-exts -fno-monomorphism-restriction \
    -fallow-overlapping-instances -fallow-undecidable-instances 
# -ddump-minimal-imports 
# flags also come in via  ../uni/uni-package.conf
# but added it here in case of compilation without uni

HC_INCLUDE = $(addprefix -i, $(INCLUDE_PATH))

logics = CASL HasCASL Isabelle Modal CoCASL COL CspCASL CASL_DL SPASS

UNI_PACKAGE_CONF = $(wildcard ../uni/uni-package.conf)
ifneq ($(strip $(UNI_PACKAGE_CONF)),)
HC_PACKAGE = -package-conf $(UNI_PACKAGE_CONF) -package uni-davinci \
    -package uni-server -DUNI_PACKAGE

# some modules from uni for haddock
# if uni/server is included also HaXml sources are needed
uni_dirs = ../uni/davinci ../uni/graphs ../uni/events \
    ../uni/reactor ../uni/util ../uni/posixutil

uni_sources = $(wildcard $(addsuffix /haddock/*.hs, $(uni_dirs))) \
    $(wildcard ../uni/htk/haddock/*/*.hs)
endif

### list of directories to run checks in
TESTDIRS += Common CASL HasCASL

PFE_TOOLDIR = $(wildcard ../programatica/tools)
ifneq ($(strip $(PFE_TOOLDIR)),)
PFE_DIRS = base/AST base/TI base/parse2 base/parse2/Lexer base/parse2/Parser \
    base/parse2/LexerGen base/parse2/LexerSpec base/tests/HbcLibraries \
    base/pretty base/syntax base/lib base/lib/Monads base/Modules base/defs \
    base/transforms base/transforms/Deriving property \
    property/syntax property/AST property/transforms \
    property/TI property/defs property/parse2 property/parse2/Parser

PFE_PATHS = $(addprefix $(PFE_TOOLDIR)/, $(PFE_DIRS))
pfe_sources = $(wildcard $(addsuffix /*hs, $(PFE_PATHS)))
PFE_PATH = $(addprefix -i, $(PFE_PATHS))
PFE_FLAGS = -package data -package text $(PFE_PATH) -DPROGRAMATICA
happy_files += $(PFE_TOOLDIR)/property/parse2/Parser/PropParser.hs

LEX_DIR = $(PFE_TOOLDIR)/base/parse2/Lexer

patch: Haskell/Programatica.patch
	patch -sNlp0 -d $(PFE_TOOLDIR) -i `pwd`/$< || exit 0

$(LEX_DIR)/HsLex.hs: $(LEX_DIR)Gen/HsLexerGen
	echo "{-# OPTIONS -w #-}" > $@
	$< >> $@

$(LEX_DIR)Gen/HsLexerGen: $(LEX_DIR)Gen/*.hs $(LEX_DIR)Spec/*.hs \
    $(LEX_DIR)/HsTokens.hs
	$(HC) --make -O -package data \
           -i$(PFE_TOOLDIR)/base/tests/HbcLibraries \
           -i$(PFE_TOOLDIR)/base/lib \
	   -i$(LEX_DIR) -i$(LEX_DIR)Gen -i$(LEX_DIR)Spec \
              $@.hs -o $@
	strip $@

logics += Haskell
derived_sources += Haskell/PreludeString.hs $(LEX_DIR)/HsLex.hs \
    $(LEX_DIR)Gen/HsLexerGen

APPENDPRELUDESTRING = utils/appendHaskellPreludeString \
    Haskell/ProgramaticaPrelude.hs

## rule for appendHaskellPreludeString
Haskell/PreludeString.hs: Haskell/PreludeString.append.hs \
    $(APPENDPRELUDESTRING)
	$(APPENDPRELUDESTRING) < $< > $@

Ast_Haskell_files = HsDeclStruct HsExpStruct HsFieldsStruct \
    HsGuardsStruct HsKindStruct HsPatStruct HsTypeStruct HsAssocStruct \
    HsModule HsName HsLiteral HsIdent

Other_PFE_files = property/AST/HsPropStruct base/defs/PNT \
    base/defs/UniqueNames base/Modules/TypedIds base/TI/TiKinds \
    base/parse2/SourceNames base/syntax/SyntaxRec \
    property/syntax/PropSyntaxStruct

Haskell_files = $(addsuffix .hs, \
    $(addprefix $(PFE_TOOLDIR)/base/AST/, $(Ast_Haskell_files)) \
    $(addprefix $(PFE_TOOLDIR)/, $(Other_PFE_files)))

## rule for ATC generation
Haskell/ATC_Haskell.der.hs: $(Haskell_files) ATC/Haskell.header.hs \
    utils/genRules
	utils/genRules -r $(rule) -o Haskell -h ATC/Haskell.header.hs \
            $(Haskell_files)

TESTDIRS += ToHaskell
endif

### Profiling (only for debugging)
### Attention every module must be compiled with profiling or the linker
### cannot link the various .o files properly. So after switching on
### Profiling, do an 'gmake real_clean; gmake'
### and comment out HC_PACKAGE variable definition above.
### Comment in the following line for switching on profiling. 
#HC_PROF = -prof -auto-all 

HCI_OPTS = $(HC_FLAGS) $(HC_INCLUDE) $(HC_PACKAGE) $(PFE_FLAGS)
HC_OPTS = $(HCI_OPTS) $(HC_PROF) -DCASLEXTENSIONS
DRIFT_OPTS = +RTS -K10m -RTS

####################################################################
## sources for hets 

non_sources = Common/LaTeX_maps.svmono.hs CspCASL/Main.hs \
    Static/LogicStructured.hs Common/CaslLanguage.hs ./Test.hs

SOURCE_PATHS = $(COMMONLIB_PATH) $(CLEAN_PATH)

sources = hets.hs $(filter-out $(non_sources), \
    $(wildcard $(addsuffix /[A-Z]*hs, $(SOURCE_PATHS))))

#endif

objects = $(sources:%.hs=%.o)

drifted_files = Syntax/AS_Architecture.hs Syntax/AS_Library.hs \
    Common/AS_Annotation.hs CASL/AS_Basic_CASL.hs Syntax/AS_Structured.hs \
    HasCASL/As.hs \
    Modal/AS_Modal.hs CoCASL/AS_CoCASL.hs COL/AS_COL.hs CASL_DL/AS_CASL_DL.hs\
    $(gendrifted_files)

genrule_header_files = $(wildcard ATC/*.header.hs)

atc_files = Common/AS_Annotation.der.hs \
    Syntax/AS_Structured.der.hs Syntax/AS_Architecture.der.hs \
    Common/GlobalAnnotations.hs Syntax/AS_Library.der.hs \
    Static/DevGraph.hs Logic/Prover.hs Proofs/Proofs.hs

atc_der_files = $(foreach file, $(atc_files), \
    ATC/$(basename $(basename $(notdir $(file)))).der.hs)

CASL_files = CASL/Sublogic.hs CASL/Morphism.hs CASL/Sign.hs \
    CASL/AS_Basic_CASL.der.hs 

HasCASL_files = HasCASL/As.hs HasCASL/Le.hs HasCASL/Morphism.hs \
    HasCASL/Sublogic.hs

Isabelle_files = Isabelle/IsaSign.hs 

Modal_files = Modal/AS_Modal.hs Modal/ModalSign.hs
CoCASL_files = CoCASL/AS_CoCASL.hs CoCASL/CoCASLSign.hs
COL_files = COL/AS_COL.hs COL/COLSign.hs
CspCASL_files = CspCASL/AS_CSP_CASL.hs CspCASL/SignCSP.hs

CASL_DL_files = CASL_DL/AS_CASL_DL.hs CASL_DL/Sign.hs

SPASS_files = SPASS/Sign.hs

atc_logic_files = $(foreach logic, $(logics), $(logic)/ATC_$(logic).der.hs)

generated_rule_files = $(atc_der_files) $(atc_logic_files)

gendrifted_files = $(patsubst %.der.hs, %.hs, $(generated_rule_files))

inline_axiom_files = Comorphisms/CASL2PCFOL.hs Comorphisms/PCFOL2FOL.hs \
    Comorphisms/Modal2CASL.hs Comorphisms/CASL2TopSort.hs

gen_inline_axiom_files = $(patsubst %.hs,%.inline.hs, $(inline_axiom_files))

derived_sources += $(drifted_files) Driver/Version.hs $(happy_files) \
    $(inline_axiom_files) Modal/ModalSystems.hs

# sources that have {-# OPTIONS -cpp #-}
cpp_sources = Common/DynamicUtils.hs \
    Common/Lib/Set.hs Common/Lib/Map.hs ATC/Set.hs\
    Isabelle/Logic_Isabelle.hs Isabelle/CreateTheories.hs \
    SPASS/Logic_SPASS.hs \
    GUI/Utils.hs hets.hs CASL/CCC/FreeTypes.hs \
    Comorphisms/LogicList.hs Comorphisms/LogicGraph.hs $(happy_files)

nondoc_sources = $(wildcard utils/DrIFT-src/*.hs) \
    $(wildcard utils/DrIFT-src/*.lhs) \
    $(wildcard utils/GenerateRules/*.hs) \
    $(wildcard utils/InlineAxioms/*.hs) \
    $(cpp_sources) $(pfe_sources) $(gen_inline_axiom_files) \
    $(genrule_header_files) $(generated_rule_files) \
    Modal/GeneratePatterns.inline.hs \
    Haskell/PreludeString.append.hs Haskell/ProgramaticaPrelude.hs \
    hxt/HXT.hs hxt/Net.hs $(patsubst %.hs, %.der.hs, $(drifted_files))

# this variable holds the modules that should be documented
doc_sources = $(filter-out $(nondoc_sources), $(sources)) \
    $(patsubst %.hs, %.hspp, $(cpp_sources)) $(uni_sources)

tax_sources = Taxonomy/AbstractGraphView.hs Taxonomy/MMiSSOntology.hs \
    Taxonomy/MMiSSOntologyGraph.hs Taxonomy/OntoParser.hs

tax_objects = $(patsubst %.hs, %.o, $(tax_sources))

####################################################################
### targets

.PHONY : all hets-opt hets-optimized clean d_clean real_clean bin_clean \
    lib_clean distclean check capa hacapa h2h clean_genRules genRules \
    taxonomy count doc apache_doc post_doc4apache \
     derivedSources install_hets install release patch

.SECONDARY : %.hs %.d $(generated_rule_files) $(gen_inline_axiom_files)

patch:

hets: $(sources) $(derived_sources)
	$(HC) --make -o $@ hets.hs $(HC_OPTS)

hets-opt: 
	$(MAKE) distclean
	$(MAKE) derivedSources
	$(MAKE) real_clean
	$(MAKE) hets-optimized

hets-optimized: $(derived_sources) 
	$(HC) --make -O -o hets hets.hs $(HC_OPTS)
	strip hets 

hets-old: $(objects)
	$(RM) $@
	$(HC) -o hets $(HC_OPTS) $(objects)

hets.cgi: $(sources) GUI/hets_cgi.hs
	ghc --make -package-conf /home/luettich/ghc-pkg/package.conf \
            -package WASH-CGI GUI/hets_cgi.hs -o hets.cgi $(HC_INCLUDE) \
            $(HC_FLAGS) -O
	strip hets.cgi

taxonomy: Taxonomy/taxonomyTool.hs $(tax_sources)
	$(HC) --make -o Taxonomy/taxonomyTool $< -ifgl $(HC_OPTS)

###############################
### TAGS files for (x)emacs 
# load them with "M-x" "visit-tags-table" from
# "HetCATS/hetcats.TAGS"
# use "M-." to search for a tag
# !!Beware this is somewhat instable, because it uses an absolute path!!
hetcats.TAGS: $(sources) 
	/home/ger/linux/ghc-5.04.2/bin/i386-unknown-linux/hasktags \
	    $(sources); mv TAGS $@; mv tags hetcats.tags

###############################
### count lines of code
count: $(sources)
	wc -l $(sources)
###############################
### Documentation via haddock
doc: docs/index.html

# generate haddock documentation with links to sources
docs/index.html: $(doc_sources)
	$(HADDOCK) $(doc_sources) -o docs -h -v \
            -i docs/base.haddock -i docs/parsec.haddock -s ../ \
            -t 'Hets - the Heterogeneous Tool Set' \
	    -p Hets-Haddock-Prologue.txt

# sources are not copied here
apache_doc:
	$(RM) docs/*.*
	cvs up -d ; echo "CVS exited with: " $$?
	$(MAKE) hets-opt
	$(MAKE) doc
	$(MAKE) post_doc4apache
	$(MAKE) o_clean
	$(MAKE) hets.cgi

post_doc4apache:
	$(PERL) utils/post_process_docs.pl docs \
            'Common.Lib.Map.html:Common.Lib._Map.html'
	cp docs/*.* a-docs/

###############################
### release management

derivedSources: $(derived_sources)

utils/DrIFT: $(DRIFT_deps)
	(cd utils/DrIFT-src; $(HC) --make DrIFT.hs -o ../DrIFT && \
            strip ../DrIFT)

utils/genRules: $(GENERATERULES_deps)
	(cd utils/GenerateRules; \
            $(HC) --make -i../DrIFT-src -i../.. $(HC_WARN) \
                GenerateRules.hs -o ../genRules && strip ../genRules)

# "hssource" for ghc-5.04.2
$(INLINEAXIOMS): $(INLINEAXIOMS_deps)
	$(HC) --make utils/InlineAxioms/InlineAxioms.hs $(HC_WARN) $(HC_PROF) \
            -package hssource -i../.. -o $(INLINEAXIOMS)
	strip $(INLINEAXIOMS)

release: 
	$(RM) -r HetCATS
	cvs -d :pserver:cvsread@cvs-agbkb.informatik.uni-bremen.de:/repository\
            co -P HetCATS
	$(RM) -r uni
	if [ -d ../uni ] ; then ln -s ../uni uni ; fi
	$(RM) -r programatica
	if [ -d ../programatica ] ; then \
            mkdir programatica; \
            ln -s ../../programatica/tools programatica/tools ; fi
	(cd HetCATS; $(MAKE) derivedSources; $(MAKE) real_clean; \
            cp Makefile Makefile.orig; \
            cp ReleaseMakefile Makefile; \
            ./clean.sh; \
            find . -name CVS -o -name \*.o -o -name \*.hi | xargs $(RM) -r; \
            $(RM) clean.*)
	tar cvf HetCATS.tar HetCATS

install-hets:
	chmod g+w hets
	cp -p hets $(INSTALLDIR)/versions/hets-`cat version_nr`
	cp -p version_nr $(INSTALLDIR)
	(cd $(INSTALLDIR); $(RM) hets; \
	    ln -s versions/hets-`cat version_nr` hets; $(RM) version_nr)

install: hets-opt install-hets

#############################
### ATC DrIFT-rule generation

genRules: $(generated_rule_files)

gen_atc_files = \
  if [ -f ATC/$(basename $(basename $(notdir $(file)))).header.hs ]; \
  then utils/genRules -r $(rule) -o ATC -h \
      ATC/$(basename $(basename $(notdir $(file)))).header.hs $(file); \
  else utils/genRules -r $(rule) -o ATC $(file); fi ;

$(atc_der_files): $(atc_files) $(genrule_header_files) utils/genRules
	$(foreach file, $(atc_files), $(gen_atc_files))

CASL/ATC_CASL.der.hs: $(CASL_files) utils/genRules
	utils/genRules -r $(rule) -o CASL $(CASL_files)

HasCASL/ATC_HasCASL.der.hs: $(HasCASL_files) utils/genRules
	utils/genRules -r $(rule) -o HasCASL $(HasCASL_files)

Isabelle/ATC_Isabelle.der.hs: $(Isabelle_files) utils/genRules
	utils/genRules -r $(rule) -o Isabelle $(Isabelle_files)

Modal/ATC_Modal.der.hs: $(Modal_files) utils/genRules
	utils/genRules -r $(rule) -o Modal $(Modal_files)

CASL_DL/ATC_CASL_DL.der.hs: $(CASL_DL_files) utils/genRules
	utils/genRules -r $(rule) -o CASL_DL $(CASL_DL_files)

CoCASL/ATC_CoCASL.der.hs: $(CoCASL_files) utils/genRules
	utils/genRules -r $(rule) -o CoCASL $(CoCASL_files)

COL/ATC_COL.der.hs: $(COL_files) utils/genRules
	utils/genRules -r $(rule) -o COL $(COL_files)

CspCASL/ATC_CspCASL.der.hs: $(CspCASL_files) utils/genRules
	utils/genRules -r $(rule) -o CspCASL $(CspCASL_files)

SPASS/ATC_SPASS.der.hs: $(SPASS_files) utils/genRules
	utils/genRules -r $(rule) -o SPASS $(SPASS_files)

rule = ShATermConvertible

clean_genRules: 
	$(RM) $(generated_rule_files) $(gendrifted_files)

###############
### clean up

clean: bin_clean o_clean

### removes *.hi and *.o in all include directories
o_clean:
	for p in $(CLEAN_PATH) ; do \
	    (cd $$p ; $(RM) *.hi *.o *.hspp) ; done

### remove binaries
bin_clean: 
	$(RM) hets
	$(RM) test_parser
	$(RM) CASL/capa
	$(RM) HasCASL/hacapa
	$(RM) Haskell/hapa
	$(RM) Haskell/hana
	$(RM) Haskell/wrap
	$(RM) ToHaskell/h2h
	$(RM) Syntax/hetpa
	$(RM) Static/hetana
	$(RM) GUI/hetdg
	$(RM) hetpa
	$(RM) hetana
	$(RM) hetdg
	$(RM) atctest2
	$(RM) atctest
	$(RM) Common/annos
	$(RM) ToHaskell/translateAna
	$(RM) Taxonomy/taxonomyTool

### additonally removes *.d (dependency files) in every include directory
### also delete *.d.bak (dependency file backups)
d_clean: clean
	for p in $(CLEAN_PATH) ; do \
	    (cd $$p ; $(RM) *.d *.d.bak) ; done

### remove files also in own libraries
lib_clean:
	for p in $(COMMONLIB_PATH) ; do \
	    (cd $$p ; $(RM) *.hi *.d *.o) ; done

### additionally removes the files that define the sources-variable
real_clean: bin_clean lib_clean clean

### additionally removes files not in CVS tree
distclean: real_clean clean_genRules d_clean
	$(RM) $(derived_sources) 
	$(RM) utils/DrIFT utils/genRules $(INLINEAXIOMS)

####################################################################
### test targets
####################################################################

### a parser to test annotation parser and Id parsers
test_parser: Common/test_parser

Common/test_parser: Common/test_parser.hs Common/AS_Annotation.der.hs
	$(HC) --make -o $@ $< $(HC_OPTS) 

### interactive
ghci: 
	$(HC)i $(HCI_OPTS)

### christian's target
### CASL parser
capa: CASL/capa

CASL/capa: CASL/capa.hs Common/*.hs CASL/*.hs
	$(HC) --make -o $@ $< $(HC_OPTS)

### HasCASL parser
hacapa: HasCASL/hacapa

HasCASL/hacapa: HasCASL/hacapa.hs Common/*.hs HasCASL/*.hs 
	$(HC) --make -o $@ $< $(HC_OPTS)

### Haskell analysis
hana: Haskell/hana

Haskell/hana: Haskell/hana.hs Haskell/HatAna.hs Haskell/PreludeString.hs
	$(HC) --make -o $@ $< $(HC_OPTS)

### Haskell to Isabelle-HOLCF translation
h2hf: ToHaskell/h2hf

ToHaskell/h2hf: ToHaskell/h2hf.hs ToHaskell/*.hs Haskell/*.hs HasCASL/*.hs Isabelle/*.hs Common/*.hs 
	$(HC) --make -o $@ $< $(HC_OPTS)

### HasCASL to Haskell translation
h2h: ToHaskell/h2h

ToHaskell/h2h: ToHaskell/h2h.hs ToHaskell/*.hs Haskell/*.hs HasCASL/*.hs
	$(HC) --make -o $@ $< $(HC_OPTS)

### HetCASL parser
hetpa: Syntax/hetpa.hs Syntax/*.hs 
	$(HC) --make -o $@ $< $(HC_OPTS)

### HetCASL parser
hetana: Static/hetana.hs Static/*.hs 
	$(HC) --make -o $@ $< $(HC_OPTS)

### ATC test system
atctest: ATC/ATCTest.hs ATC/*.hs 
	$(HC) --make -o $@ $< $(HC_OPTS)

atctest2: ATC/ATCTest2.hs Common/SimpPretty.hs Common/ATerm/*.hs \
    Common/Lib/*.hs
	$(HC) --make -o $@ $< $(HC_OPTS)

### ATerm.Lib test system
atermlibtest: Common/ATerm/ATermLibTest.hs Common/SimpPretty.hs \
    Common/ATerm/*.hs Common/Lib/*.hs
	$(HC) --make -o $@ $< $(HC_OPTS) $(EXTRA_HC_OPTS)

hatermdiff: Common/ATerm/ATermDiffMain.hs Common/SimpPretty.hs \
    Common/ATerm/*.hs Common/Lib/*.hs
	$(HC) --make -o $@ $< $(HC_OPTS) $(EXTRA_HC_OPTS)

### OWL_DL test target
OWL_DL/readAStest: OWL_DL/ToHaskellAS.hs Common/ATerm/*.hs \
   Common/Lib/*.hs OWL_DL/*.hs
	$(HC) --make -o $@ $< $(HC_OPTS) $(EXTRA_HC_OPTS)

### HetCASL with dev graph
hetdg: GUI/hetdg.hs $(drifted_files) *.hs 
	$(HC) --make -o $@ $< $(HC_OPTS)

### run tests in other directories
check:
	for i in $(TESTDIRS); do $(MAKE) -C $$i check; done

####################################################################
## Preparing the version of HetCATS
Driver/Version.hs: Driver/Version.in version_nr
	$(RM) $@
	$(PERL) utils/build_version.pl version_nr < Driver/Version.in > $@
	chmod 444 $@

## two hardcoded dependencies for a correct generation of Version.hs
Driver/Options.hs Driver/WriteFn.hs Driver/ReadFn.hs: Driver/Version.hs
hets.hs: Driver/Version.hs
####################################################################
## rules for DrIFT
.SUFFIXES:

%: %.hs
	$(HC) --make -o $@ $<

%.hs: %.y
	$(HAPPY) -o $@.tmp $<
	echo "{-# OPTIONS -w #-}" > $@
	cat $@.tmp >> $@
	$(RM) $@.tmp

%.hs: %.der.hs utils/DrIFT
	$(RM) $@
	($(DRIFT_ENV);	export DERIVEPATH; $(DRIFT) $(DRIFT_OPTS) $< > $@)
	chmod 444 $@

## rules for inlineAxioms
%.hs: %.inline.hs $(INLINEAXIOMS)
	$(RM) $@
	$(INLINEAXIOMS) $< > $@
	chmod 444 $@

## rule for cpp and haddock 
%.hspp: %.hs
	$(HC) -E -cpp -DUNI_PACKAGE -optP -P $<

## compiling rules for object and interface files
%.o %.hi: %.hs
	$(HC) -c $< $(HC_OPTS)

%.o %.hi: %.lhs
	$(HC) -c $< $(HC_OPTS)

## compiling rules for dependencies
%.d : %.hs
	$(HC) -M $< $(HC_OPTS) -optdep-f -optdep$@

%.d : %.lhs
	$(HC) -M $< $(HC_OPTS) -optdep-f -optdep$@

## rule for Modal/ModalSystems.hs needed for ModalLogic Translation
Modal/ModalSystems.hs: Modal/GeneratePatterns.inline.hs.in \
    utils/genTransMFormFunc.pl $(INLINEAXIOMS)
	$(RM) $@
	$(PERL) utils/genTransMFormFunc.pl $< $@
	chmod 444 $@
