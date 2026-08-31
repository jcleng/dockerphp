FROM registry.cn-hangzhou.aliyuncs.com/jcleng/library-node:20
# TO registry.cn-hangzhou.aliyuncs.com/jcleng/mcpproxy
# 设置环境变量
ENV GO_VERSION=1.22.5
ENV GOPATH=/go
ENV PATH=$PATH:/usr/local/go/bin:$GOPATH/bin

# 安装基础依赖
RUN apt-get update && apt-get install -y \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 安装 Golang
RUN curl -fsSL https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz -o go.tar.gz \
    && tar -C /usr/local -xzf go.tar.gz \
    && rm go.tar.gz

# 安装 mcpproxy-go
RUN go install github.com/smart-mcp-proxy/mcpproxy-go/cmd/mcpproxy@latest

# 暴露端口
EXPOSE 8080

# 启动 mcpproxy serve
CMD ["mcpproxy", "serve", "--host", "0.0.0.0", "--port", "8080"]
