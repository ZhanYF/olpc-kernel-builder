#!/bin/bash
# Author: Daniel Drake <dsd@laptop.org>
#
# FIXME: deletion of old kernels perhaps isnt what we want to do when
# this becomes official
# FIXME: chris wants access to build dirs after builds are done, for ease
# of making small changes and compiling new kernels
set -e
set -x
git_clone="/home/cjb/kernels/olpc-2.6"
rpm_basedir="/home/cjb/kernels/rpms-out"
syncdir="/home/cjb/kernels/rpms-sync"
builddir="/home/cjb/kernels/rpm-build"

build_configs="olpc-2.6.35,xo_1-kernel-rpm,f14-xo1 olpc-2.6.35,xo_1_5-kernel-rpm,f14-xo1.5"

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
	rpm_outdir=$tgtdir/build-$datestamp
	rm -rf $rpm_outdir
	mkdir -p $rpm_outdir
	git checkout remotes/origin/$branch
	git_head=$(git log -1 --format=%H)
	[ -e $tgtdir/lastbuild ] && last_git_head=$(<$tgtdir/lastbuild)
	if [[ $git_head == $last_git_head ]]; then
		echo "Already built kernel $git_head"
	else
		# Do build
		make RPMSDIR="$rpm_outdir" BUILDDIR="$builddir" clean distclean
		if make RPMSDIR="$rpm_outdir" BUILDDIR="$builddir" $target; then
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
	ln $tgtdir/build-*/*/* $repopath
done

# do sync
KEY="-i /home/cjb/.ssh/id_rsa_kernels"
REMOTE="kernels@dev.laptop.org"
for repo in $syncdir/*; do
	repo_bname=$(basename $repo)
	# FIXME add --delete-after when moved to ~kernels (i.e. no other rpm
	# packages other than kernels live in public_rpms)
	rsync -e "ssh $KEY" --delay-updates -av $repo/ $REMOTE:public_rpms/$repo_bname
done
