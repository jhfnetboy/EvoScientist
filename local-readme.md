# jhfnetboy add for local research

  # 一键配置（只需跑一次）
  ./scripts/proxy.sh setup                    # 默认 claude-sonnet-4-6
  ./scripts/proxy.sh setup claude-opus-4-6    # 指定模型

  # 日常使用
  ./scripts/proxy.sh start                    # 交互模式
  ./scripts/proxy.sh start -p "hello"         # 单次查询
  ./scripts/proxy.sh serve --workdir ~/research --auto-approve  # 24小时挂机
  ./scripts/proxy.sh stop                     # 停 ccproxy
  ./scripts/proxy.sh status                   # 检查状态
