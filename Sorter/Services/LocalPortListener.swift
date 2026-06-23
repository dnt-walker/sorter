import Foundation
import NIO
import NIOSSH
import Citadel

/// 로컬 TCP 포트를 바인딩하고, 들어오는 연결을 SSH DirectTCPIP 채널로 포워딩한다.
final class LocalPortListener {
    private var serverChannel: Channel?

    func start(localPort: Int, sshClient: SSHClient, remoteHost: String, remotePort: Int) async throws {
        let bootstrap = ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .serverChannelOption(ChannelOptions.backlog, value: 128)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .childChannelInitializer { localChannel in
                localChannel.pipeline.addHandler(
                    TunnelBridgeHandler(
                        sshClient: sshClient,
                        remoteHost: remoteHost,
                        remotePort: remotePort
                    )
                )
            }

        serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: localPort).get()
    }

    func stop() async {
        try? await serverChannel?.close().get()
        serverChannel = nil
    }
}

/// 로컬 연결과 SSH DirectTCPIP 채널을 양방향으로 이어주는 핸들러.
/// NIO 이벤트 루프에서 호출되므로 외부에서 별도 동기화 없이 상태를 접근한다.
final class TunnelBridgeHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let sshClient: SSHClient
    private let remoteHost: String
    private let remotePort: Int

    private var sshChannel: Channel?
    private var pendingReads: [ByteBuffer] = []

    init(sshClient: SSHClient, remoteHost: String, remotePort: Int) {
        self.sshClient = sshClient
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }

    func channelActive(context: ChannelHandlerContext) {
        let localChannel = context.channel
        let el = context.eventLoop
        let sshClient = self.sshClient
        let remoteHost = self.remoteHost
        let remotePort = self.remotePort

        Task {
            do {
                let originAddr = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
                let sshChan = try await sshClient.createDirectTCPIPChannel(
                    using: SSHChannelType.DirectTCPIP(
                        targetHost: remoteHost,
                        targetPort: remotePort,
                        originatorAddress: originAddr
                    ),
                    initialize: { channel in
                        channel.pipeline.addHandler(RelayToLocalHandler(localChannel: localChannel))
                    }
                )

                el.execute {
                    self.sshChannel = sshChan
                    for buf in self.pendingReads {
                        sshChan.writeAndFlush(buf, promise: nil)
                    }
                    self.pendingReads.removeAll()
                }
            } catch {
                el.execute { localChannel.close(promise: nil) }
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buf = unwrapInboundIn(data)
        if let sshChannel = sshChannel {
            sshChannel.writeAndFlush(buf, promise: nil)
        } else {
            pendingReads.append(buf)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        sshChannel?.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

/// SSH 채널에서 받은 데이터를 로컬 채널로 전달하는 핸들러.
final class RelayToLocalHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let localChannel: Channel

    init(localChannel: Channel) {
        self.localChannel = localChannel
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buf = unwrapInboundIn(data)
        localChannel.writeAndFlush(buf, promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        localChannel.close(promise: nil)
    }
}
