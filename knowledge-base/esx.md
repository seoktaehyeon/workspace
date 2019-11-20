#### 列出所有正在运行的的VM
```bash
esxcli vm process list
```

#### 列出所有的VM
```bash
vim-cmd vmsvc/getallvms
```

#### 获取指定VM的快照
```bash
vim-cmd vmsvc/snapshot.get $vm_id
```

#### 恢复快照后不开机
```bash
vim-cmd vmsvc/snapshot.revert $vm_id $snapshotId suppressPowerOn
```

#### 打开VM
```bash
vim-cmd vmsvc/power.on $vm_id
```

#### 查找VM ID
```bash
vim-cmd vmsvc/getallvms | grep baoxian-sz-1
```

#### 清理虚拟机
```bash
vim-cmd vmsvc/power.off $vm_id
vim-cmd vmsvc/destroy $vm_id
```
