# 微信类 IM MVP

本目录定义 `wechat` 分支的 MVP 业务层。WuKongIM 继续负责 WebSocket 长连接、个人/群消息投递、消息持久化和同步；本业务层负责身份、用户资料、群组权限及消息业务元数据。

## 范围

- 用户注册：手机号、邮箱或用户名三选一
- 登录与 JWT 鉴权
- 用户资料与头像 URL
- 在线状态查询（由 WuKongIM 连接状态作为来源）
- 个人聊天：`channel_id = 对方 uid`，`channel_type = person`
- 群聊：创建、查看、加成员、移除成员、退出、角色权限、禁言、解散
- 消息业务元数据：撤回、已读/未读、历史消息查询
- 消息内容类型：text、image、file

暂不包含语音/视频通话、红包、朋友圈和端到端加密。

## 分层约定

```text
客户端 -> 业务 API (/api/v1) -> 用户/群组/权限数据库
客户端 -> WuKongIM WebSocket -> 消息收发与同步
```

客户端登录后使用业务 API 返回的 `im_token` 连接 WuKongIM。不要把密码或业务 JWT 直接当作消息内容发送。图片和文件先上传到对象存储，再发送 URL、名称和大小等消息字段。

## API 最小集合

除特别说明外，接口都需要：`Authorization: Bearer <access_token>`。

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| POST | `/api/v1/auth/register` | 注册 |
| POST | `/api/v1/auth/login` | 登录并取得 IM token |
| GET | `/api/v1/users/me` | 当前用户资料 |
| PATCH | `/api/v1/users/me` | 修改昵称、头像 |
| GET | `/api/v1/users/:uid/presence` | 查询在线状态 |
| POST | `/api/v1/groups` | 创建群 |
| GET | `/api/v1/groups/:group_id` | 群详情与成员 |
| POST | `/api/v1/groups/:group_id/members` | 添加成员 |
| DELETE | `/api/v1/groups/:group_id/members/:uid` | 移除成员 |
| POST | `/api/v1/groups/:group_id/leave` | 退出群 |
| PATCH | `/api/v1/groups/:group_id/members/:uid` | 设置角色/禁言 |
| DELETE | `/api/v1/groups/:group_id` | 解散群 |
| POST | `/api/v1/conversations/:channel_type/:channel_id/read` | 更新已读位置 |
| POST | `/api/v1/messages/:message_id/revoke` | 撤回消息 |
| GET | `/api/v1/messages/:channel_type/:channel_id` | 查询消息历史 |

个人聊天使用 `channel_type=person`，`channel_id=对方 uid`；群聊使用 `channel_type=group`，`channel_id=group_id`。���成员变更必须由业务服务端校验后同步到 WuKongIM 的订阅者列表，客户端不能自行订阅任意群。

## 登录响应示例

```json
{
  "access_token": "<jwt>",
  "expires_in": 604800,
  "user": { "uid": "u_123", "nickname": "Alice", "avatar_url": "" },
  "im_token": "<wukongim-token>",
  "im_endpoint": "wss://im.example.com/ws"
}
```

JWT 至少包含 `sub`（uid）、`jti`、`iat`、`exp`，密钥必须从环境变量读取，禁止提交到仓库。生产环境密码应使用 Argon2id 或 bcrypt，接口需要限流并对手机号/邮箱做验证码校验。

## 消息格式

```json
{
  "type": "text",
  "content": "你好"
}
```

```json
{
  "type": "image",
  "url": "https://cdn.example.com/a.jpg",
  "width": 800,
  "height": 600,
  "size": 123456
}
```

```json
{
  "type": "file",
  "url": "https://cdn.example.com/a.pdf",
  "name": "合同.pdf",
  "size": 123456
}
```

撤回和已读属于业务指令：撤回需要校验消息发送者及时间窗口，成功后通过 WuKongIM command message 通知在线客户端；已读只保存每个用户/频道的最后已读消息序号或消息 ID。

## 开发顺序

1. 按 `schema.sql` 创建业务数据库并实现注册、登录、JWT 中间件。
2. 实现用户资料和头像上传签名接口。
3. 集成 WuKongIM 登录 token、个人频道和群频道。
4. 实现群成员权限同步及群管理接口。
5. 实现历史消息、撤回、已读位置。
6. 增加限流、审计日志、对象存储和推送。

SQL 只是业务层的起始 schema；WuKongIM 消息表不要在业务数据库中重复维护。
