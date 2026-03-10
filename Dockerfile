# 基于指定的ROCm基础镜像
FROM swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/rocm/dev-ubuntu-24.04:7.2-complete

LABEL description="ROCm 7.1.1 + Latest Ollama Service"

# 设置环境变量，避免交互提示，指定Ollama安装目录
ENV DEBIAN_FRONTEND=noninteractive
ENV OLLAMA_HOME=/root/.ollama
ENV PATH="$PATH:/usr/local/bin"

# 更新系统包并安装必要依赖（curl用于下载Ollama，ca-certificates确保HTTPS下载）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    zstd \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 下载并安装最新版Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# 创建Ollama数据目录（避免启动时目录不存在）
RUN mkdir -p ${OLLAMA_HOME} && chmod 777 ${OLLAMA_HOME}

# 暴露Ollama默认端口（供外部访问）
EXPOSE 11434

# 设置容器启动命令，后台运行Ollama服务并保持容器不退出
CMD ["sh", "-c", "ollama serve & tail -f /dev/null"]
