#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Author: Will v.stone@163.com
## Dependence:
pip install TestlinkApiClient

import os
from xml.dom.minidom import parseString
try:
    from TestlinkApiClient.tlxmlrpc import TestlinkClient
except:
    os.system('pip install TestlinkApiClient')
    from TestlinkApiClient.tlxmlrpc import TestlinkClient
try:
    import requests
except:
    os.system('pip install requests')
    import requests
    
jira_url = ''
jira_user = ''
jira_password = ''
ids = {
    # 'JIRA Issue ID': 'TestLink Case External ID',
}
tl_project_name = '' 
tl_suite_name = ''

session = requests.session()
session.auth = (jira_user, jira_password)
for key in ids.keys():
    jira_id = key
    tl_id = ids[key]
    tl_steps = list()
    rsp = session.get('%s/si/jira.issueviews:issue-xml/%s/%s.xml' % (jira_url, jira_id, jira_id))
    elements = parseString(rsp.content.decode('utf-8'))
    tl_case_name = elements.getElementsByTagName('summary')[0].firstChild.data.strip()
    for item in elements.getElementsByTagName('orderId'):
        tl_steps.append({'step_number': item.firstChild.data})
    i = 0
    for item in elements.getElementsByTagName('step')[1::2]:
        tl_steps[i]['actions'] = item.firstChild.data.strip()
        i += 1
    i = 0
    for item in elements.getElementsByTagName('result'):
        tl_steps[i]['expected_results'] = item.firstChild.data.strip()
        i += 1
    if tl_id:
        testlink.update_step(tl_id, tl_steps)
    else:
        testlink.create_case(tl_project_name, tl_suite_name, tl_case_name, steps=tl_steps)

