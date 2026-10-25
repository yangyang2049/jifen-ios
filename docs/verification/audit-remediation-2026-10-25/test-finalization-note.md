终轮878项单测与3项iPhone UI均已通过；Xcode随后自动执行的simctl diagnose --timeout=600长时间未退出，仅读诊断子进程被终止后xcodebuild正常exit 0，结果包完整写入。未中断任何测试进程。iPad独立UI测试exit 0。
