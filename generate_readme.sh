#!/bin/bash
_raw_link='https://raw.githubusercontent.com/seoktaehyeon/workspace/master'
_blob_link='https://github.com/seoktaehyeon/workspace/blob/master'
_dir_list=$(ls)

echo '# Workspace' > README.md
echo '> *This document is generated by scripts*<br>' >> README.md
echo '> *Please contact v.stone@163.com if there is any mistake*' >> README.md

for _dir in $_dir_list
do
    echo ""
    if [[ -d $_dir ]]; then 
        echo "$_dir is a dir, list it"
        echo "## $_dir" >> README.md
        for _file in $(ls $_dir)
        do
            _file_type=$(echo "$_file" | awk -F '.' '{print $NF}')
            if [[ "$_file_type" == "md" ]]; then
                _file_link="${_blob_link}/${_dir}/${_file}"
            else
                _file_link="${_raw_link}/${_dir}/${_file}"
            fi
            echo "${_file}: ${_file_link}"
            echo "- [$_file](${_file_link})" >> README.md
        done
    else
        echo "$_dir is not a dir, skip it"
    fi
done
