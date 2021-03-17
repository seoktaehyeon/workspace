#!/bin/bash
cd ..
for post_file in $(ls _posts)
do
    output=$(cat _posts/$post_file)
    tags=$(echo $output | awk -F '---' '{print $2}' | awk -F 'tags:' '{print $2}' | sed 's/-/ /g')
    for tag in $tags
    do
        [[ -f tag/$tag.md ]] || {
            cat <<EOF > tag/$tag.md
---
layout: tag
sitemap: false
title: "话题：$tag"
tags:
  - $tag
---
EOF
        }
    done
done
