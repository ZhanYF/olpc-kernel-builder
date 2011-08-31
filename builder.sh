#!/bin/bash
# Author: Daniel Drake <dsd@laptop.org>
#
# FIXME: deletion of old kernels perhaps isnt what we want to do when
# this becomes official
# FIXME: chris wants access to build dirs after builds are done, for ease
# of making small changes and compiling new kernels
set -e
basedir="$HOME/kernels"
git_clone="$basedir/olpc-kernel"
rpm_basedir="$basedir/rpms-out"
syncdir="$basedir/rpms-sync"
export builddir="$basedir/rpm-build"
ssh_dest="kernels@dev.laptop.org"

if [ $# -lt 1 ]; then
	echo "1 parameter required: config file"
	exit 1
fi

. $1

if [ -z "$build_configs" ]; then
	echo "build_configs must be defined in config file"
	exit 1
fi

set -x
datestamp=$(date +%Y%m%d%H%M%S)

# Make a tree to sync
mkdir -p $syncdir
rm -rf $syncdir/*

cd $git_clone
git fetch

for config in $build_configs; do
	oIFS=$IFS
	IFS=,
	set $config
	IFS=$oIFS
	branch=$1
	target=$2
	reponame=$3

	echo "Building $branch $target into $reponame"

	tgtdir=$rpm_basedir/$branch/$target
	export rpm_outdir=$tgtdir/build-$datestamp
	rm -rf $rpm_outdir
	mkdir -p $rpm_outdir
	git checkout remotes/origin/$branch
	git_head=$(git log -1 --format=%H)
	[ -e $tgtdir/lastbuild ] && last_git_head=$(<$tgtdir/lastbuild)
	if [[ $git_head == $last_git_head ]]; then
		echo "Already built kernel $git_head"
	else
		# Do build
		if [ -x olpc/buildrpm ]; then
			rm -rf $builddir
			mkdir -p $builddir
			./olpc/buildrpm $target
			retcode=$?
		else
			# Legacy build from Makefile, likely to hit issues in #10994
			make SRPMSDIR="$rpm_outdir" RPMSDIR="$rpm_outdir" BUILDDIR="$builddir" clean distclean
			make SRPMSDIR="$rpm_outdir" RPMSDIR="$rpm_outdir" BUILDDIR="$builddir" $target
			retcode=$?
		fi

		if [ $retcode = 0 ]; then
			echo $git_head > $tgtdir/lastbuild
		else
			echo "Failed to build $branch $target" >&2
			rm -rf $rpm_outdir
		fi
	fi

	# Clean up old builds
	ls -d --sort=time $tgtdir/build-* | tail -n +10 | xargs --no-run-if-empty rm -rf

	# Send all recent builds to be synced
	repopath=$syncdir/$reponame
	mkdir -p $repopath
	ln $tgtdir/build-*/*/* $tgtdir/build-*/*.src.rpm $repopath
done

# do sync
for repo in $syncdir/*; do
	repo_bname=$(basename $repo)
	# FIXME add --delete-after when moved to ~kernels (i.e. no other rpm
	# packages other than kernels live in public_rpms)
	rsync -e "ssh $ssh_args" --delay-updates -av $repo/ $ssh_dest:public_rpms/$repo_bname
done
