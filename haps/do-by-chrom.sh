#!/bin/bash

set -e

base=$1
threads=20
ref=./hg38.fa
vars=./HGSVC.haps.vcf.gz

if [[ -z "$base" ]] ; then
    echo "No base specified" 1>&2
    exit 1
fi

#chroms=$(cat $ref.fai | cut -f 1)
#chroms=$(for i in $(seq 1 22; echo X; echo Y); do echo chr${i}; done)
chroms=chr21

if [[ ! -e $base.threads.xg ]] ; then
    echo "constructing"
    echo $chroms | tr ' ' '\n' | parallel -j $threads "vg construct -r $ref -v $vars -R {} -C -m 32 -a -f > $base.{}.vg"

    echo "node id unification"
    vg ids -j -m $base.mapping $(for i in $chroms; do echo $base.$i.vg; done)
    cp $base.mapping $base.mapping.backup

    echo "indexing haplotypes"
    echo $chroms | tr ' ' '\n' | parallel -j $threads "vg index -x $base.{}.xg -G $base.{}.gbwt -v $vars -F $base.{}.threads $base.{}.vg"

    chrom_count="$(echo $chroms | tr ' ' '\n' | wc -l)"
    if [[ "${chrom_count}" -gt "1" ]] ; then
        echo "merging GBWT"
        vg gbwt -m -f -o $base.all.gbwt $(for i in $chroms; do echo $base.$i.gbwt; done)
    else
        echo "using only gbwt"
        cp $base.$chroms.gbwt $base.all.gbwt
    fi

    echo "extracting threads as paths"
    for i in $chroms; do ( vg mod $(for f in $(vg paths -L -x $base.$i.xg ); do echo -n ' -r '$f; done) $base.$i.vg; vg paths -x $base.$i.xg -g $base.$i.gbwt -T -V ) | vg view -v - >$base.$i.threads.vg; done

    echo "re-indexing haps+threads"
    vg index -x $base.threads.xg $(for i in $chroms; do echo $base.$i.threads.vg; done)
fi    

if [[ ! -e  $base.threads.gcsa ]] ; then
    echo "pruning"
    echo $chroms | tr ' ' '\n' | parallel -j $threads "vg prune -r $base.{}.threads.vg > $base.{}.threads.prune.vg"

    echo "building gcsa2 index"
    mkdir -p work
    TMPDIR=. vg index  -g $base.threads.gcsa -Z 4096 -k 16 -b work -p -t $threads $(for i in $chroms; do echo $base.$i.threads.prune.vg; done)
    rm -rf work *.prune.vg
fi
