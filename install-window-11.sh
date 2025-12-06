#!/bin/bash

# ==============================================================================
# SCRIPT CÀI ĐẶT WINDOWS 11 KVM TRÊN UBUNTU 24.04 (FINAL FIX)
# Tác giả: Ma Seo Sen
# ==============================================================================

# --- CẤU HÌNH (BẠN CÓ THỂ THAY ĐỔI) ---
VM_NAME="Windows11_KVM"
VM_CPU="16"
VM_RAM="16384"        # 8GB,16384=16GB,32768=32GB
VM_DISK_SIZE="150"    # 150GB
DISK_NAME="win11_disk.qcow2"
VNC_PORT="5900"
WIN11_ISO_PATH=""    # Để trống để script hướng dẫn tải

# --- MÀU SẮC ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- HÀM KIỂM TRA LỖI ---
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Lỗi: $1${NC}"
        exit 1
    fi
}

echo -e "${GREEN}=== BẮT ĐẦU QUÁ TRÌNH THIẾT LẬP WINDOWS 11 KVM (V2) ===${NC}"

# 1. KIỂM TRA QUYỀN ROOT
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Lỗi: Script này phải được chạy với quyền root (sudo).${NC}"
   exit 1
fi

# 2. BẬT REPO VÀ CÀI ĐẶT GÓI (SỬA LỖI THIẾU GÓI)
echo -e "${YELLOW}[1/6] Cài đặt các gói phần mềm cần thiết...${NC}"

# Bật repo universe để tải cabextract
add-apt-repository universe -y > /dev/null 2>&1
apt update -y

# Cài đặt đầy đủ (Đã sửa tên cabinet-extract -> cabextract)
apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst swtpm swtpm-tools ovmf wget \
aria2 cabextract wimtools chntpw genisoimage unzip file

check_error "Không thể cài đặt các gói phần mềm. Kiểm tra kết nối mạng."

# Kích hoạt dịch vụ ảo hóa
systemctl enable --now libvirtd

# 3. TẢI VIRTIO DRIVER
echo -e "${YELLOW}[2/6] Kiểm tra VirtIO Driver...${NC}"
if [ ! -f "virtio-win.iso" ]; then
    echo "Đang tải virtio-win.iso..."
    wget -q --show-progress https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
    check_error "Tải virtio-win.iso thất bại."
else
    echo -e "${GREEN}Đã có file virtio-win.iso.${NC}"
fi

# 4. XỬ LÝ WINDOWS 11 ISO (SỬA LỖI LINK TẢI)
download_from_uup() {
    echo -e "${YELLOW}--- TẢI WINDOWS 11 TỪ UUP DUMP ---${NC}"
    echo "Hướng dẫn lấy link:"
    echo "1. Truy cập: https://uupdump.net"
    echo "2. Chọn bản Win 11 muốn tải -> Next -> Chọn ngôn ngữ -> Next"
    echo "3. Chọn Edition (Professional) -> Next"
    echo "4. Copy link trên thanh địa chỉ trình duyệt"
    echo "   Ví dụ: https://uupdump.net/download.php?id=xxx&pack=en-us&edition=professional"
    echo ""
    read -p "Dán link UUP Dump vào đây: " UUP_URL

    if [ -z "$UUP_URL" ]; then
        echo -e "${RED}Chưa nhập link!${NC}"
        exit 1
    fi

    # Xóa file cũ nếu có
    rm -f uup_dump.zip
    rm -rf win11_build

    # Phân tích link để lấy thông tin
    if [[ "$UUP_URL" == *"download.php"* ]]; then
        # Lấy các tham số từ URL
        UUP_ID=$(echo "$UUP_URL" | grep -oP 'id=\K[^&]+')
        UUP_PACK=$(echo "$UUP_URL" | grep -oP 'pack=\K[^&]+')
        UUP_EDITION=$(echo "$UUP_URL" | grep -oP 'edition=\K[^&]+')
        
        # Nếu không lấy được, dùng giá trị mặc định
        [ -z "$UUP_PACK" ] && UUP_PACK="en-us"
        [ -z "$UUP_EDITION" ] && UUP_EDITION="professional"
        
        if [ -z "$UUP_ID" ]; then
            echo -e "${RED}Không thể lấy ID từ link. Vui lòng kiểm tra lại.${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}Đã phát hiện:${NC}"
        echo "  ID: $UUP_ID"
        echo "  Ngôn ngữ: $UUP_PACK"
        echo "  Edition: $UUP_EDITION"
        
        # Tạo link API để tải script package
        API_URL="https://uupdump.net/get.php?id=${UUP_ID}&pack=${UUP_PACK}&edition=${UUP_EDITION}&autodl=2"
        
        echo -e "${YELLOW}Đang tải script từ UUP Dump API...${NC}"
        wget --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
             --content-disposition \
             "$API_URL" -O uup_dump.zip 2>&1
        
    elif [[ "$UUP_URL" == *".zip"* ]] || [[ "$UUP_URL" == *"get.php"* ]]; then
        # Link trực tiếp đến file ZIP
        echo -e "${YELLOW}Đang tải file ZIP trực tiếp...${NC}"
        wget --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
             "$UUP_URL" -O uup_dump.zip 2>&1
    else
        echo -e "${RED}Link không hợp lệ. Vui lòng dùng link từ uupdump.net${NC}"
        exit 1
    fi

    # Kiểm tra file đã tải
    if [ ! -f "uup_dump.zip" ]; then
        echo -e "${RED}Không tải được file!${NC}"
        exit 1
    fi

    # Kiểm tra xem có phải file ZIP thật không
    FILE_TYPE=$(file uup_dump.zip)
    if [[ "$FILE_TYPE" != *"Zip archive"* ]]; then
        echo -e "${RED}==================================================${NC}"
        echo -e "${RED}LỖI: File tải về không phải ZIP.${NC}"
        echo -e "${RED}Thử phương pháp thay thế...${NC}"
        echo -e "${RED}==================================================${NC}"
        rm -f uup_dump.zip
        
        # Thử phương pháp thay thế: dùng curl với redirect
        echo -e "${YELLOW}Thử lại với curl...${NC}"
        curl -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
             -o uup_dump.zip \
             "https://uupdump.net/get.php?id=${UUP_ID}&pack=${UUP_PACK}&edition=${UUP_EDITION}&autodl=2"
        
        FILE_TYPE=$(file uup_dump.zip)
        if [[ "$FILE_TYPE" != *"Zip archive"* ]]; then
            echo -e "${RED}Vẫn không tải được. Vui lòng tải thủ công:${NC}"
            echo "1. Mở trình duyệt, truy cập: https://uupdump.net/download.php?id=${UUP_ID}&pack=${UUP_PACK}&edition=${UUP_EDITION}"
            echo "2. Chọn 'Download and convert to ISO' -> 'Create download package'"
            echo "3. Tải file ZIP về và đặt tại: $(pwd)/uup_dump.zip"
            echo "4. Chạy lại script này"
            exit 1
        fi
    fi

    echo -e "${GREEN}Tải file ZIP thành công!${NC}"
    echo "Giải nén và chạy script tạo ISO..."
    unzip -o uup_dump.zip -d win11_build
    cd win11_build
    
    # Cấp quyền chạy
    chmod +x uup_download_linux.sh 2>/dev/null
    
    # Kiểm tra file script tồn tại
    if [ ! -f "uup_download_linux.sh" ]; then
        echo -e "${RED}Không tìm thấy uup_download_linux.sh trong package${NC}"
        ls -la
        exit 1
    fi
    
    echo -e "${YELLOW}Đang build ISO (Mất khoảng 20-40 phút)... Vui lòng đợi.${NC}"
    ./uup_download_linux.sh
    
    # Tìm file ISO kết quả (có thể là .iso hoặc .ISO)
    BUILT_ISO=$(find . -maxdepth 1 -iname "*.iso" | head -n 1)
    if [ -z "$BUILT_ISO" ]; then
        echo -e "${RED}Lỗi: Build thất bại. Không thấy file ISO nào được tạo ra.${NC}"
        echo "Các file hiện có:"
        ls -la
        exit 1
    fi
    
    mv "$BUILT_ISO" ../win11_custom.iso
    cd ..
    rm -rf win11_build uup_dump.zip
    
    WIN11_ISO_PATH="$(pwd)/win11_custom.iso"
    echo -e "${GREEN}Build thành công: $WIN11_ISO_PATH${NC}"
}

# Menu chọn nguồn ISO
if [ -z "$WIN11_ISO_PATH" ] || [ ! -f "$WIN11_ISO_PATH" ]; then
    echo -e "${YELLOW}[3/6] Cấu hình file cài đặt Windows 11${NC}"
    echo "1. Nhập đường dẫn file ISO có sẵn trên máy."
    echo "2. Tự tải và tạo ISO từ UUP Dump (Cần mạng mạnh & kiên nhẫn)."
    read -p "Chọn (1/2): " CHOICE

    case $CHOICE in
        1)
            read -p "Nhập đường dẫn file ISO (VD: /root/win11.iso): " WIN11_ISO_PATH
            if [ ! -f "$WIN11_ISO_PATH" ]; then
                echo -e "${RED}File không tồn tại!${NC}"
                exit 1
            fi
            ;;
        2)
            download_from_uup
            ;;
        *)
            echo "Lựa chọn không hợp lệ."
            exit 1
            ;;
    esac
fi

# 5. TẠO MÁY ẢO
echo -e "${YELLOW}[4/6] Đang tạo máy ảo...${NC}"

if [ ! -f "$DISK_NAME" ]; then
    qemu-img create -f qcow2 "$DISK_NAME" "${VM_DISK_SIZE}G"
fi

# Lệnh virt-install chuẩn
virt-install \
  --name "$VM_NAME" \
  --ram "$VM_RAM" \
  --vcpus "$VM_CPU" \
  --os-variant win10 \
  --disk path="$(pwd)/$DISK_NAME",bus=virtio,format=qcow2 \
  --disk path="$(pwd)/virtio-win.iso",device=cdrom,bus=sata \
  --cdrom "$WIN11_ISO_PATH" \
  --network network=default,model=virtio \
  --graphics vnc,listen=0.0.0.0,port="$VNC_PORT" \
  --tpm backend.type=emulator,backend.version=2.0,model=tpm-tis \
  --boot uefi \
  --noautoconsole \
  --check all=off

check_error "Không thể khởi tạo máy ảo."

# 6. KẾT THÚC
HOST_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}=======================================================${NC}"
echo -e "${GREEN}   CÀI ĐẶT THÀNH CÔNG! MÁY ẢO ĐANG CHẠY.${NC}"
echo -e "${GREEN}=======================================================${NC}"
echo -e "Thông tin kết nối VNC:"
echo -e "  IP:   ${YELLOW}$HOST_IP${NC}"
echo -e "  Port: ${YELLOW}$VNC_PORT${NC}"
echo ""
echo -e "${RED}LƯU Ý QUAN TRỌNG KHI CÀI WIN:${NC}"
echo "1. Khi cài đặt đến đoạn chọn ổ đĩa, danh sách sẽ TRỐNG."
echo "2. Bấm 'Load Driver' -> Browse."
echo "3. Chọn ổ CD 'virtio-win' -> thư mục 'amd64' -> 'w11'."
echo "4. Chọn driver hiện ra rồi bấm Next -> Ổ cứng sẽ xuất hiện."
echo ""
