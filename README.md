# ROS 2 Jazzy: Cyclone DDS vs Fast DDS 네트워크 설정 가이드

본 문서는 ROS 2 환경에서 Cyclone DDS와 Fast DDS의 네트워크 인터페이스 제어 메커니즘 차이를 비교하고, 상황별(Local, Wired, Wireless) XML 설정 방법을 요약한 가이드입니다.

---

## 1. 아키텍처 제어 방식 요약

| 비교 항목 | Cyclone DDS | Fast DDS |
| :--- | :--- | :--- |
| **설정 태그** | `<General>/<Interfaces>/<NetworkInterface>` | `<transport_descriptor>/<interfaceWhiteList>` |
| **다중 인터페이스 처리** | **우선순위 기반 단일 선점 (Failover)**<br>`priority`가 가장 높은 1개 인터페이스만 활성화 | **다중 바인딩 동시 통신 (Multi-homing)**<br>목록에 등록된 모든 인터페이스로 동시 송수신 |
| **로컬(IPC) 통신** | 외부 IP가 잡혀도 커널 루프백 바이패스로 소통<br>(오프라인 시 최후 수단으로 `lo` 사용) | `<transport_id>shm_transport</transport_id>`가 켜져 있으면 네트워크와 무관하게 RAM(Zero-Copy) 처리 |

---

## 2. 케이스별 XML 설정 가이드

### 케이스 1. 단일 PC 로컬 격리 (외부 통신 원천 차단)
외부 네트워크(공유기 등)로 패킷 유출을 막고 PC 내부 프로세스 간 통신만 허용할 때 사용합니다.

**Cyclone DDS** (루프백 `lo` 인터페이스만 강제 지정)
```xml
<General>
    <Interfaces>
        <NetworkInterface name="lo" priority="10" multicast="true" presence_required="true"/>
    </Interfaces>
    <AllowMulticast>true</AllowMulticast>
</General>
```

**Fast DDS** (화이트리스트에 `lo`와 `127.0.0.1`만 바인딩)
```xml
<transport_descriptor>
    <transport_id>udp_transport</transport_id>
    <type>UDPv4</type>
    <interfaceWhiteList>
        <interface>lo</interface>
        <address>127.0.0.1</address>
    </interfaceWhiteList>
</transport_descriptor>
```

---

### 케이스 2. 유선 이더넷 전용 (Wired Only)
Wi-Fi 간섭 없이 고대역폭 센서(LiDAR, 카메라) 또는 메인 제어기와의 안정적인 통신을 보장할 때 사용합니다.

**Cyclone DDS** (유선 단독 지정 및 에러 강제)
```xml
<General>
    <Interfaces>
        <NetworkInterface name="enx8cb0e9e7ed99" priority="20" multicast="default" presence_required="true"/>
    </Interfaces>
    <AllowMulticast>true</AllowMulticast>
</General>
```

**Fast DDS** (유선 인터페이스만 등록하여 Wi-Fi 소켓 생성 차단)
```xml
<transport_descriptor>
    <transport_id>udp_transport</transport_id>
    <type>UDPv4</type>
    <interfaceWhiteList>
        <interface>enx8cb0e9e7ed99</interface>
    </interfaceWhiteList>
</transport_descriptor>
```

---

### 케이스 3. 무선 Wi-Fi 전용 (Wireless Only)
무선 공유기를 통해 모니터링 PC나 원격 오퍼레이터와 통신할 때 사용합니다.

**Cyclone DDS** (`wlan0` 지정 및 노드 깜빡임 방지)
```xml
<General>
    <Interfaces>
        <NetworkInterface name="wlan0" priority="10" multicast="default" presence_required="true"/>
    </Interfaces>
    <AllowMulticast>true</AllowMulticast>
</General>
<Discovery>
    <LeaseDuration>8s</LeaseDuration>
</Discovery>
```

**Fast DDS** (`wlan0` 등록 및 Lease 주기 완화)
```xml
<transport_descriptor>
    <transport_id>udp_transport</transport_id>
    <type>UDPv4</type>
    <interfaceWhiteList>
        <interface>wlan0</interface>
    </interfaceWhiteList>
</transport_descriptor>
<!-- <builtin>/<discovery_config> 내부 -->
<leaseDuration>
    <sec>8</sec>
</leaseDuration>
```

---

### 케이스 4. 유선 + 무선 복합 운용 (실무 권장)

**Cyclone DDS: 우선순위 자동 전환 (Failover)**
유선 케이블이 연결되면 기가비트 유선을 사용하고, 케이블을 분리하면 끊김 없이 Wi-Fi로 자동 전환됩니다.
```xml
<General>
    <Interfaces>
        <!-- 1순위: 유선 (연결 시 최우선 점유) -->
        <NetworkInterface name="enx8cb0e9e7ed99" priority="20" multicast="default" presence_required="false"/>
        <!-- 2순위: 무선 (유선 미연결 시 백업 전환) -->
        <NetworkInterface name="wlan0" priority="10" multicast="default" presence_required="false"/>
        <!-- 3순위: 로컬 (네트워크 단절 시 최후 수단) -->
        <NetworkInterface name="lo" priority="1" multicast="default" presence_required="false"/>
    </Interfaces>
    <AllowMulticast>true</AllowMulticast>
</General>
```

**Fast DDS: 다중 망 동시 활성화 (Multi-homing)**
유선(센서 전용 대역)과 무선(로봇 관제 대역)이 분리되어 양쪽 대역의 ROS 2 토픽을 동시에 송수신해야 할 때 사용합니다.
```xml
<transport_descriptor>
    <transport_id>udp_transport</transport_id>
    <type>UDPv4</type>
    <interfaceWhiteList>
        <!-- 두 네트워크에 각각 소켓을 생성하여 동시 통신 -->
        <interface>enx8cb0e9e7ed99</interface>
        <interface>wlan0</interface>
    </interfaceWhiteList>
</transport_descriptor>
```

---

## 3. 핵심 운용 주의점

1. **Fast DDS의 동일 서브넷 루프 주의**
   Fast DDS에서 유선과 무선이 동일한 IP 서브넷(예: `192.168.0.xxx` 대역)에 연결된 상태로 둘 다 화이트리스트에 넣으면, 동일한 멀티캐스트 패킷이 양쪽으로 중복 발생하여 Wi-Fi 대역폭 낭비가 심해집니다. 유/무선 분리망이 아니라면 인터페이스 지정을 비워두고 OS 기본 라우팅을 따르는 것이 안전합니다.
2. **Cyclone DDS의 장치명 변경 주의**
   Cyclone DDS는 장치 이름이 일치하지 않으면 탐색을 건너뜁니다. 반드시 `presence_required="false"`를 병행하여 특정 인터페이스가 없더라도 다음 순위(무선 $\rightarrow$ 로컬)로 넘어갈 수 있도록 구성해야 통신 단절을 방지할 수 있습니다.
3. **ROS 2 표준 환경 변수와의 결합**
   `ros2_mode` 커스텀 스크립트 명령어를 활용하면 XML을 매번 수정할 필요 없이 `ros2_mode local`(단일 PC 격리), `ros2_mode subnet`(서브넷 탐색), `ros2_mode unicast <IP>`(지정 타깃 통신)를 실시간으로 전환할 수 있습니다.