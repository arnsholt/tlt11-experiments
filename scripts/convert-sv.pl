#!/usr/bin/env perl

use strict;
use warnings;

use Lingua::CoNLLX;
use List::MoreUtils qw/any/;

my %posmap = qw(
++ konj
AB adv
AJ adj
AN subst
AV verb
BV verb
EN det
FV verb
GV verb
HV verb
I? clb
IC <anf>
IG clb
IK <komma>
IM inf-merke
IP clb
IQ clb
IS clb
IT <strek>
IU clb
KV verb
MN subst
MV verb
NN subst
PO pron
PR prep
PU symb
QV verb
RO det
SP adj
SV verb
UK sbu
VN subst
VV verb
WV verb
XX ukjent
YY interj
);
my %tpadj = qw/AT 1 DT 1 PA 1/;

my %depmap = qw(
++ KONJ
+F KOORD
AA ADV
AG ADV
AN APP
AT ATR
BS ADV
C+ ADV
CA ADV
CC KOORD
CJ KOORD
DB ADV
DT DET
EF ATR
EO POBJ
ES PSUBJ
ET ATR
FO FOBJ
FS FSUBJ
FV FINV
I? IP
IC IK
IG IP
IK IK
IO IOBJ
IP IP
IQ IP
IR IK
IS IK
IT IK
IU IP
IV INFV
JC IK
JG IK
JR IK
JT IK
MA ADV
MD ADV
NA ADV
OA ADV
OO DOBJ
PA PUTFYLL
PL ADV
SP SPRED
SS SUBJ
ST IK
UK SBU
VA KONJ
VG INFV
VO DOBJ
VS SUBJ
XA ADV
XF ADV
XT ADV
XX SPRED
YY INTERJ
);

my %nominal = qw/subst 1
                 pron 1
                 det 1
                 symb 1
                 adj 1/;
my %verbal = qw/verb 1
                adv 1
                prep 1/;

my $corpus = Lingua::CoNLLX->new(file => $ARGV[0]);

for my $s (@{$corpus->sentences}) {
    $s->traverse(\&mapping, order => 'prefix');

    $s->iterate(\&convert);

    name_map($s->token(0));

    print $s;
    print "\n\n";
}

sub mapping {
    return if $_->id == 0;
    posmap(@_);
    relmap(@_);
}

sub posmap {
    my $t = $_;
    my $pos = $t->postag;
    my $rel = $t->deprel;

    if(exists $posmap{$pos}) {
        $pos = $posmap{$pos};
    }
    # ID #inherits pos-tag from head
    elsif($pos eq 'ID') {
        $pos = $t->head->postag;
        $t->feats($t->head->feats);
    }
    # IR <parentes-beg> #or <parentes-slutt>!# must be disambiguated
    elsif($pos eq 'IR') {
        $pos = $t->form eq '('? '<parentes-beg>':
               $t->form eq ')'? '<parentes-slutt>':
                                '<parentes-???>';
    }
    # PN: proper name. subst and prop in feats column.
    elsif($pos eq 'PN') {
        $pos = 'subst';
        $t->feats(['prop']);
    }
    # TP #adj or verb? check deprel: #AT:adj, DT:adj, PA:adj, else:verb
    elsif($pos eq 'TP') {
        $pos = exists $tpadj{$rel}? 'adj': 'verb';
    }
    else {
        $pos = "$pos???";
    }

    $t->postag($pos);
    $t->cpostag($pos);
}

sub relmap {
    my $t = $_;
    my $pos = $t->postag;
    my $rel = $t->deprel;

    if(exists $depmap{$rel}) {
        $rel = $depmap{$rel};
    }
    # IM	#assigned mapped deprel of head
    elsif($rel eq 'IM') {
        $rel = $t->head->deprel;
    }
    # KA	#if nominal (subst, pron) or adjectival (adj) : PUTFYLL, 
    # 	#if verbal: if head is nominal: ATR, if head is verbal: ADV
    elsif($rel eq 'KA') {
        if(nominal($pos) or adj($pos)) { $rel = 'PUTFYLL' }
        elsif(verb($pos)) {
            my $head = $t->head->postag;
            if(nominal($head)) { $rel = 'ATR' }
            elsif(verb($head)) { $rel = 'ADV' }
            else               { $rel = "$rel/$head???" }
        }
        else { $rel = "$rel-$pos???" }
    }
    # MS	#if head is verbal and dep is konj: KOORD, 
    # 	#if lemma is member of {avslutte, bemerke, erklære, forklare,
    # 	fortelle, hevde, hviske, mene, si, skrive, spørre, tro, understreke,
    # 	uttale, vite}: PAR, else: ADV
    elsif($rel eq 'MS') {
		my $head = $t->head->postag;
        if(verb($head) && $pos eq 'konj') {
            $rel = 'KOORD';
		}
        # TODO: Lemma check...
        elsif(undef) {
            $rel = 'PAR';
        }
        else {
            $rel = 'ADV';
        }
    }
    # PT	#if head has lemma "selv": DET, else: ADV
    elsif($rel eq 'PT') {
        # TODO: Lemma check...
        if(undef) {
            $rel = 'DET';
        }
        else {
            $rel = 'ADV';
        }
    }
    # +A	#if head is nominal: ATR, if head is verbal: ADV
    # RA	#if head is nominal: ATR, if head is verbal: ADV
    # TA	#if head is nominal: ATR, if head is verbal: ADV
    elsif($rel eq '+A' or $rel eq 'RA' or $rel eq 'TA') {
        my $head = $t->head->postag;
        if(nominal($head)) { $rel = 'ATR' }
        elsif(verb($head)) { $rel = 'ADV' }
        else               { $rel = "$rel/$head???" }
    }
    # HD	#if pos of head is proper noun: ATR, if pos of head is det: inherits deprel _and_ head from head
    #     #if pos of head is prep: PUTFYLL, else: ADV
    elsif($rel eq 'HD') {
        my $head = $t->head->postag;
        if($head eq 'subst' && any {$_ eq 'prop'} @{$t->head->feats || []}) {
            $rel = 'ATR';
        }
        elsif($head eq 'det') {
            $rel = $t->head->deprel;
            $t->head($t->head->head);
        }
        elsif($head eq 'prep') {
            $rel = 'PUTFYLL';
        }
        else {
            $rel = 'ADV';
        }
    }
    elsif($rel eq 'ROOT') {
        $rel = $pos eq 'verb'?   'FINV':
               $pos eq 'interj'? 'INTERJ':
                                 'FRAG';
    }
    else {
        $rel = "$rel???";
    }

    $t->deprel($rel);
}

sub convert {
    my $inf = $_;
    my $pos = $inf->postag;

    # Only interested in inf-merke.
    return if $pos ne 'inf-merke';

    # Anything inf-merke should have a verb head and no children. Anything
    # that doesn't match this we ignore.
    return if $inf->head->postag ne 'verb' or @{$inf->children} > 0;

    # In Talbanken, infinitive verbs are the head, while in the Norwegian
    # treebank, the infinitive marker is the head and the verb a dependent of
    # it.
    my $verb = $inf->head;
    my $head = $verb->head;

    # Remove $verb from $head's list of children and $inf from the verb's
    # list.
    $head->_delete_child($verb);
    $verb->_delete_child($inf);

    # Add $inf as a child of $head and $verb as child of $inf.
    $head->_add_child($inf);
    $inf->_add_child($verb);

    # Set $inf and $verb's head fields to the right values.
    $inf->head($head);
    $verb->head($inf);
}

# TODO: Convert proper name chains.
sub name_map {
    my ($t) = @_;

    my $all = 1;
    my @names = (); # Temp. cache of all-name children.
    for my $child (@{$t->children}) {
        my $namep = name_map($child);
        $all = $all && $namep;
        push @names, $child if $namep;
    }

    # If not all children are all-name, convert all of them that are.
    map { convert_name($_) } @names if not $all;

    # Is this an all-name subgraph?
    return $all;
}

sub convert_name {
    my ($root) = @_;

    my $nodes = subtree_nodes($root);
    for my $n (@$nodes) {
        trace($n);
    }
    trace("\n");
}

sub subtree_nodes {
    my ($t, $nodes) = @_;
    my $sort;
    if(not defined $nodes) {
        $nodes = [];
        $sort = 1;
    }

    push @$nodes, $t;
    map { subtree_nodes($_) } @{$t->children};

    return [sort { $a->id <=> $b->id } @$nodes] if $sort;
}

sub trace {
    say STDERR @_;
}

sub nominal { exists $nominal{$_[0]} }
sub adj     { $_[0] eq 'adj' }
sub verb    { exists $verbal{$_[0]} }
