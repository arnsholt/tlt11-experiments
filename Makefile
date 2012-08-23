SHELL=bash

# Magical number that splits 120806_bm_gullkorpus.conll 90/10.
NO_SPLIT_N=67566
DIRS=corpora models parsed scores

SV_NS=    1     2    5 \
	     10    20   50 \
	    100   200  500 \
	   1000  2000 5000 \
	  10000 11042
SV_LEX_SCORES=$(foreach N, $(SV_NS), scores/no-sv-lex-$N.scores)
SV_DELEX_SCORES=$(foreach N, $(SV_NS), scores/no-sv-delex-$N.scores)

DA_NS=    1     2    5 \
	     10    20   50 \
	    100   200  500 \
	   1000  2000 5000 5190
DA_LEX_SCORES=$(foreach N, $(DA_NS), scores/no-da-lex-$N.scores)
DA_DELEX_SCORES=$(foreach N, $(DA_NS), scores/no-da-delex-$N.scores)

# Never delete intermediate files.
.SECONDARY:
.PHONY: all

all: no-sv-lex.dat no-sv-delex.dat no-da-lex.dat no-da-delex.dat

# Parser targets:
models/sv-%.mco: corpora/sv-train-%.conll | models
	cd models && malt -c `basename $@` -m learn -l liblinear -a nivreeager -i ../$<

models/da-%.mco: corpora/da-train-%.conll | models
	cd models && malt -c `basename $@` -m learn -l liblinear -a nivreeager -i ../$<

parsed/no-sv-conv-%.conll: models/sv-conv-%.mco corpora/no-test-bare.conll | parsed
	cd models && malt -c `basename $<` -m parse -i ../corpora/no-test-bare.conll -o ../$@

parsed/no-%.conll: models/%.mco corpora/no-test.conll | parsed
	cd models && malt -c `basename $<` -m parse -i ../corpora/no-test.conll -o ../$@

scores/no-sv-conv-%.scores: parsed/no-sv-conv-%.conll corpora/no-test-bare.conll | scores
	./scripts/eval.pl -q -s $< -g corpora/no-test-bare.conll > $@

scores/%.scores: parsed/%.conll corpora/no-test.conll | scores
	./scripts/eval.pl -q -s $< -g corpora/no-test.conll > $@

# Data aggregation:
no-sv-lex.dat: $(SV_LEX_SCORES)
no-sv-delex.dat: $(SV_DELEX_SCORES)
no-da-lex.dat: $(DA_LEX_SCORES)
no-da-delex.dat: $(DA_DELEX_SCORES)
%.dat:
	./scripts/extract-scores.pl $^ | sed 's/[^0-9 ]*\([0-9]\+\)[^0-9 \t]*/\1/' > $@

# Data conversion targets:
corpora/sv-train-lex.conll: data/swedish/talbanken05/train/swedish_talbanken05_train.conll scripts/pos-map.pl | corpora
	./scripts/pos-map.pl --source=sv $< > $@
corpora/sv-train-lex-%.conll: corpora/sv-train-lex.conll
	awk -vcount=$* -f scripts/corpus-select.awk $< > $@
corpora/sv-train-delex-%.conll: corpora/sv-train-delex.conll
	awk -vcount=$* -f scripts/corpus-select.awk $< > $@
corpora/sv-train-conv-lex.conll: data/swedish/talbanken05/train/swedish_talbanken05_train.conll scripts/convert-sv.pl | corpora
	./scripts/convert-sv.pl $< > $@

corpora/da-train-lex.conll: data/danish/ddt/train/danish_ddt_train.conll scripts/pos-map.pl | corpora
	./scripts/pos-map.pl --source=da $< > $@
corpora/da-train-lex-%.conll: corpora/da-train-lex.conll
	awk -vcount=$* -f scripts/corpus-select.awk $< > $@
corpora/da-train-delex-%.conll: corpora/da-train-delex.conll
	awk -vcount=$* -f scripts/corpus-select.awk $< > $@

corpora/%-delex.conll: corpora/%-lex.conll scripts/delex.awk
	awk -f scripts/delex.awk $< > $@

# TODO: Make sure using a delex parser on lex data doesn't perform differently.
corpora/no-train.conll: 120806_bm_gullkorpus.conll scripts/pos-map.pl
	./scripts/pos-map.pl --source=no <(sed 's/ /_/g' $<) | head -n $(NO_SPLIT_N) > $@

corpora/no-test.conll: 120806_bm_gullkorpus.conll scripts/pos-map.pl
	./scripts/pos-map.pl --source=no <(sed 's/ /_/g' $<) | tail -n +`expr $(NO_SPLIT_N) + 1` > $@

corpora/no-test-bare.conll: 120806_bm_gullkorpus.conll
	sed 's/ /_/g' $< | tail -n +`expr $(NO_SPLIT_N) + 1` > $@

# Misc. targets:
$(DIRS):
	mkdir $@

data/swedish/talbanken05/train/swedish_talbanken05_train.conll \
data/danish/ddt/train/danish_ddt_train.conll: data

interset: interset.zip
	unzip $<
	mkdir -p interset/lib/tagset/no
	cp conll.pm interset/lib/tagset/no

interset.zip:
	wget http://ufal.mff.cuni.cz/~zeman/download.php?f=interset-v1.2.zip -O $@

# TODO: Czech data?
data:
	curl http://ilk.uvt.nl/conll/data/danish/conll06_data_danish_ddt_train_v1.1.tar.bz2 | tar xj
	curl http://ilk.uvt.nl/conll/data/swedish/conll06_data_swedish_talbanken05_train_v1.1.tar.bz2 | tar xj
	curl http://ilk.uvt.nl/conll/data/conll06_data_free_test.tar.bz2 | tar xj
	patch data/swedish/talbanken05/train/swedish_talbanken05_train.conll talbanken.patch
