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

# 4. XỬ LÝ WINDOWS 11 ISO

# Hàm tải ISO trực tiếp từ Microsoft (NHANH & ỔN ĐỊNH)
download_from_microsoft() {
    echo -e "${YELLOW}--- TẢI WINDOWS 11 ISO TRỰC TIẾP TỪ MICROSOFT ---${NC}"
    
    # Cài đặt jq nếu chưa có
    apt install -y jq curl > /dev/null 2>&1
    
    echo "Đang lấy link tải từ Microsoft..."
    
    # Sử dụng Fido script để lấy link tải trực tiếp từ Microsoft
    # Link này lấy Windows 11 Multi-edition ISO
    
    LANG_CODE="en-us"
    echo "Chọn ngôn ngữ:"
    echo "1. English (en-us) - Mặc định"
    echo "2. Vietnamese (vi-vn)"
    echo "3. Chinese Simplified (zh-cn)"
    read -p "Chọn (1/2/3) [Enter = English]: " LANG_CHOICE
    
    case $LANG_CHOICE in
        2) LANG_CODE="vi-vn" ;;
        3) LANG_CODE="zh-cn" ;;
        *) LANG_CODE="en-us" ;;
    esac
    
    echo -e "${GREEN}Ngôn ngữ: $LANG_CODE${NC}"
    
    # Tải Fido script
    echo "Đang tải công cụ Fido..."
    curl -sL "https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1" -o /tmp/Fido.ps1
    
    # Sử dụng phương pháp thay thế: tải từ link có sẵn
    # Microsoft cung cấp link tải ISO qua trang chính thức
    
    echo -e "${YELLOW}Đang tạo link tải Windows 11...${NC}"
    
    # Tạo session và lấy link
    SESSION_ID=$(curl -s "https://www.microsoft.com/en-us/api/controls/contentinclude/html?pageId=a8f8f489-4c7f-463a-9ca6-5cff94d8d041&host=www.microsoft.com&segments=software-download,windows11&query=&action=getskuinformationbyproductedition&sessionId=&productEditionId=2935&sdVersion=2" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        | grep -oP 'id="session-id" value="\K[^"]+' 2>/dev/null)
    
    if [ -z "$SESSION_ID" ]; then
        echo -e "${YELLOW}Không lấy được session từ Microsoft. Dùng link backup...${NC}"
        
        # Sử dụng link từ các mirror đáng tin cậy
        echo ""
        echo "Chọn nguồn tải:"
        echo "1. Massgrave (Mirror nhanh, khuyên dùng)"
        echo "2. Archive.org (Ổn định)"
        echo "3. Nhập link ISO thủ công"
        read -p "Chọn (1/2/3): " MIRROR_CHOICE
        
        case $MIRROR_CHOICE in
            1)
                # Link từ massgrave - Windows 11 23H2
                ISO_URL="https://drive.massgrave.dev/Win11_23H2_English_x64v2.iso"
                if [ "$LANG_CODE" == "vi-vn" ]; then
                    ISO_URL="https://drive.massgrave.dev/Win11_23H2_Vietnamese_x64.iso"
                elif [ "$LANG_CODE" == "zh-cn" ]; then
                    ISO_URL="https://drive.massgrave.dev/Win11_23H2_Chinese_Simplified_x64.iso"
                fi
                ;;
            2)
                # Link từ Archive.org
                ISO_URL="https://archive.org/download/win-11-english-x-64v-2/Win11_23H2_English_x64v2.iso"
                ;;
            3)
                echo "Nhập link ISO Windows 11 (phải là link trực tiếp .iso):"
                read -p "Link: " ISO_URL
                ;;
            *)
                ISO_URL="https://drive.massgrave.dev/Win11_23H2_English_x64v2.iso"
                ;;
        esac
    fi
    
    if [ -z "$ISO_URL" ]; then
        echo -e "${RED}Không có link tải!${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Link tải: $ISO_URL${NC}"
    echo -e "${YELLOW}Đang tải Windows 11 ISO (~6GB)... Vui lòng đợi.${NC}"
    
    # Tải ISO với aria2c (nhanh hơn wget)
    if command -v aria2c &> /dev/null; then
        aria2c -x 16 -s 16 -k 1M --file-allocation=none \
               --continue=true \
               -o "win11.iso" \
               "$ISO_URL"
    else
        wget --continue --show-progress -O "win11.iso" "$ISO_URL"
    fi
    
    if [ ! -f "win11.iso" ] || [ $(stat -c%s "win11.iso" 2>/dev/null || echo 0) -lt 1000000000 ]; then
        echo -e "${RED}Tải ISO thất bại hoặc file không hoàn chỉnh!${NC}"
        rm -f win11.iso
        exit 1
    fi
    
    WIN11_ISO_PATH="$(pwd)/win11.iso"
    echo -e "${GREEN}Tải thành công: $WIN11_ISO_PATH${NC}"
}

# Hàm tải từ UUP Dump (backup)
download_from_uup() {
    echo -e "${YELLOW}--- TẢI WINDOWS 11 TỪ UUP DUMP ---${NC}"
    echo -e "${RED}LƯU Ý: Phương pháp này chậm và hay bị lỗi!${NC}"
    echo "Hướng dẫn lấy link:"
    echo "1. Truy cập: https://uupdump.net"
    echo "2. Chọn bản Win 11 muốn tải -> Next -> Chọn ngôn ngữ -> Next"
    echo "3. Chọn Edition (Professional) -> Next"
    echo "4. Copy link trên thanh địa chỉ trình duyệt"
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
    if [[ "$UUP_URL" == *"download.php"* ]] || [[ "$UUP_URL" == *"selectlang.php"* ]]; then
        # Lấy các tham số từ URL
        UUP_ID=$(echo "$UUP_URL" | grep -oP 'id=\K[^&]+')
        UUP_PACK=$(echo "$UUP_URL" | grep -oP 'pack=\K[^&]+')
        UUP_EDITION=$(echo "$UUP_URL" | grep -oP 'edition=\K[^&]+')
        
        [ -z "$UUP_PACK" ] && UUP_PACK="en-us"
        [ -z "$UUP_EDITION" ] && UUP_EDITION="professional"
        
        if [ -z "$UUP_ID" ]; then
            echo -e "${RED}Không thể lấy ID từ link!${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}ID: $UUP_ID | Ngôn ngữ: $UUP_PACK | Edition: $UUP_EDITION${NC}"
        
        API_URL="https://uupdump.net/get.php?id=${UUP_ID}&pack=${UUP_PACK}&edition=${UUP_EDITION}&autodl=2"
        
        echo -e "${YELLOW}Đang tải package từ UUP Dump...${NC}"
        wget --timeout=60 --tries=3 \
             --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
             "$API_URL" -O uup_dump.zip 2>&1
    else
        wget --timeout=60 --tries=3 \
             --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
             "$UUP_URL" -O uup_dump.zip 2>&1
    fi

    # Kiểm tra file ZIP
    if [ ! -f "uup_dump.zip" ]; then
        echo -e "${RED}Không tải được file!${NC}"
        exit 1
    fi
    
    FILE_TYPE=$(file uup_dump.zip)
    if [[ "$FILE_TYPE" != *"Zip archive"* ]]; then
        echo -e "${RED}File tải về không phải ZIP! Thử phương pháp Microsoft thay thế.${NC}"
        rm -f uup_dump.zip
        download_from_microsoft
        return
    fi

    echo "Giải nén..."
    unzip -o uup_dump.zip -d win11_build
    cd win11_build
    
    chmod +x uup_download_linux.sh 2>/dev/null
    
    if [ ! -f "uup_download_linux.sh" ]; then
        echo -e "${RED}Không tìm thấy script build!${NC}"
        cd ..
        download_from_microsoft
        return
    fi
    
    echo -e "${YELLOW}Đang build ISO (20-60 phút)...${NC}"
    echo -e "${YELLOW}Nếu bị treo quá 30 phút, nhấn Ctrl+C và chạy lại script, chọn phương pháp Microsoft.${NC}"
    
    # Chạy với timeout
    timeout 3600 ./uup_download_linux.sh
    
    BUILT_ISO=$(find . -maxdepth 1 -iname "*.iso" | head -n 1)
    if [ -z "$BUILT_ISO" ]; then
        echo -e "${RED}Build thất bại!${NC}"
        cd ..
        echo "Chuyển sang phương pháp Microsoft..."
        download_from_microsoft
        return
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
    echo "1. Tải ISO từ Microsoft/Mirror (KHUYÊN DÙNG - Nhanh ~10 phút)"
    echo "2. Tải từ UUP Dump (Chậm, hay lỗi - 30-60 phút)"
    echo "3. Nhập đường dẫn file ISO có sẵn trên máy"
    read -p "Chọn (1/2/3): " CHOICE

    case $CHOICE in
        1)
            download_from_microsoft
            ;;
        2)
            download_from_uup
            ;;
        3)
            read -p "Nhập đường dẫn file ISO (VD: /root/win11.iso): " WIN11_ISO_PATH
            if [ ! -f "$WIN11_ISO_PATH" ]; then
                echo -e "${RED}File không tồn tại!${NC}"
                exit 1
            fi
            ;;
        *)
            echo "Lựa chọn không hợp lệ. Dùng mặc định: Microsoft"
            download_from_microsoft
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
