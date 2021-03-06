#!/bin/bash
_github_raw_link='https://raw.githubusercontent.com/seoktaehyeon/workspace/master'
_github_blob_link='https://github.com/seoktaehyeon/workspace/blob/master'
_gitee_raw_link='https://gitee.com/vstone/workspace/raw/master'
_gitee_blob_link='https://gitee.com/vstone/workspace/blob/master'
_dir_list=$(ls)

echo '# Will Workspace' > README.md
echo '> *This document is generated by scripts*<br>' >> README.md
echo '> *Please contact v.stone@163.com if there is any mistake*' >> README.md

for _dir in ${_dir_list}
do
    [[ "${_dir}" == "static" ]] && continue
    echo ""
    if [[ -d "${_dir}" ]]; then
        echo "$_dir is a dir, list it"
        echo "## $_dir" >> README.md
        echo "File | GitHub | Gitee" >> README.md
        echo "---- | ---- | ----" >> README.md
        for _file in $(ls ${_dir})
        do
            _file_type=$(echo "$_file" | awk -F '.' '{print $NF}')
            if [[ "$_file_type" == "md" ]]; then
                _file_link_github="${_github_blob_link}/${_dir}/${_file}"
                _file_link_gitee="${_gitee_blob_link}/${_dir}/${_file}"
                echo -e "${_file}:\n${_file_link_github}\n${_file_link_gitee}"
                echo "${_file} | *[ Read ](${_file_link_github})* | *[ Read ](${_file_link_gitee})*" >> README.md
            else
                _file_link_github="${_github_raw_link}/${_dir}/${_file}"
                _file_link_gitee="${_gitee_raw_link}/${_dir}/${_file}"
                echo -e "${_file}:\n${_file_link_github}\n${_file_link_gitee}"
                echo "${_file} | *[ Raw Link ](${_file_link_github})* | *[ Raw Link ](${_file_link_gitee})*" >> README.md
            fi
        done
    else
        echo "$_dir is not a dir, skip it"
    fi
done

