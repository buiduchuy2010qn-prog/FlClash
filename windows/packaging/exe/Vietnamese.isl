; *** Inno Setup version 6.1.0+ Chinese Simplified messages ***
;
; To download user-contributed translations of this file, go to:
;   https://jrsoftware.org/files/istrans/
;
; Note: When translating this text, do not add periods (.) to the end of
; messages that didn't have them already, because on those messages Inno
; Setup adds the periods automatically (appending a period would result in
; two periods being displayed).
;
; Maintained by Zhenghan Yang
; Email: 847320916@QQ.com
; Translation based on network resource
; The latest Translation is on https://github.com/kira-96/Inno-Setup-Chinese-Simplified-Translation
;

[LangOptions]
; The following three entries are very important. Be sure to read and 
; understand the '[LangOptions] section' topic in the help file.
LanguageName=Tiếng Việt
; If Language Name display incorrect, uncomment next line
; LanguageName=<7B80><4F53><4E2D><6587>
; About LanguageID, to reference link:
; https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-lcid/a9eac961-e77d-41a6-90a5-ce1a8b0cdb9c
LanguageID=$042A
LanguageCodePage=1258
; If the language you are translating to requires special font faces or
; sizes, uncomment any of the following entries and change them accordingly.
DialogFontName=Segoe UI
;DialogFontSize=8
WelcomeFontName=Segoe UI
;WelcomeFontSize=12
TitleFontName=Segoe UI
;TitleFontSize=29
;CopyrightFontName=Arial
;CopyrightFontSize=8

[Messages]

; *** 应用程序标题
SetupAppTitle=Cài đặt
SetupWindowTitle=Cài đặt - %1
UninstallAppTitle=Gỡ cài đặt
UninstallAppFullTitle=Gỡ cài đặt %1

; *** Misc. common
InformationTitle=Thông tin
ConfirmTitle=Xác nhận
ErrorTitle=Lỗi

; *** SetupLdr messages
SetupLdrStartupMessage=Trình cài đặt chuẩn bị cài đặt %1 lên máy tính của bạn. Bạn có muốn tiếp tục?
LdrCannotCreateTemp=Không thể tạo tệp tạm thời. Đã hủy cài đặt.
LdrCannotExecTemp=Không thể chạy tệp trong thư mục tạm. Đã hủy cài đặt.
HelpTextNote=

; *** 启动错误消息
LastErrorMessage=%1.%n%nLỗi %2: %3
SetupFileMissing=Thiếu tệp %1 trong thư mục cài đặt. Vui lòng khắc phục hoặc tải lại bộ cài.
SetupFileCorrupt=Tệp cài đặt bị hỏng. Vui lòng tải lại bản cài đặt mới.
SetupFileCorruptOrWrongVer=Tệp cài đặt bị hỏng hoặc không tương thích với phiên bản trình cài đặt này.
InvalidParameter=Tham số dòng lệnh không hợp lệ:%n%n%1
SetupAlreadyRunning=Trình cài đặt đang chạy.
WindowsVersionNotSupported=Ứng dụng này không hỗ trợ phiên bản Windows hiện tại trên máy tính của bạn.
WindowsServicePackRequired=Ứng dụng này yêu cầu %1 Gói dịch vụ %2 trở lên.
NotOnThisPlatform=Ứng dụng này không chạy được trên %1.
OnlyOnThisPlatform=Ứng dụng này phải chạy trên %1.
OnlyOnTheseArchitectures=Ứng dụng này chỉ cài đặt được trên Windows hỗ trợ các kiến trúc:%n%n%1
WinVersionTooLowError=Ứng dụng này yêu cầu %1 phiên bản %2 trở lên.
WinVersionTooHighError=Ứng dụng này không thể cài trên %1 phiên bản %2 trở lên.
AdminPrivilegesRequired=Bạn cần đăng nhập bằng tài khoản Quản trị viên (Administrator) để cài đặt.
PowerUserPrivilegesRequired=Bạn cần quyền Quản trị viên hoặc Power Users để cài đặt ứng dụng này.
SetupAppRunningError=Phát hiện %1 đang chạy.%n%nVui lòng đóng tất cả cửa sổ đang mở, sau đó nhấn OK để tiếp tục hoặc Hủy để thoát.
UninstallAppRunningError=Phát hiện %1 đang chạy.%n%nVui lòng đóng tất cả cửa sổ đang mở, sau đó nhấn OK để tiếp tục hoặc Hủy để thoát.

; *** 启动问题
PrivilegesRequiredOverrideTitle=Chọn chế độ cài đặt
PrivilegesRequiredOverrideInstruction=Chọn chế độ cài đặt
PrivilegesRequiredOverrideText1=%1 có thể cài cho mọi người dùng (cần quyền quản trị) hoặc chỉ cho tài khoản hiện tại.
PrivilegesRequiredOverrideText2=%1 chỉ có thể cài cho tài khoản hiện tại hoặc cho mọi người dùng (cần quyền quản trị).
PrivilegesRequiredOverrideAllUsers=Cài cho tất cả người dùng (&A)
PrivilegesRequiredOverrideAllUsersRecommended=Cài cho tất cả người dùng (&A) (khuyên dùng)
PrivilegesRequiredOverrideCurrentUser=Chỉ cài cho tôi (&M)
PrivilegesRequiredOverrideCurrentUserRecommended=Chỉ cài cho tôi (&M) (khuyên dùng)

; *** 其它错误
ErrorCreatingDir=Không thể tạo thư mục "%1".
ErrorTooManyFilesInDir=Không thể tạo tệp trong thư mục "%1" vì có quá nhiều tệp

; *** 安装程序公共消息
ExitSetupTitle=Thoát cài đặt
ExitSetupMessage=Quá trình cài đặt chưa hoàn tất. Nếu thoát ngay bây giờ, ứng dụng sẽ chưa được cài đặt.%n%nBạn có muốn thoát không?
AboutSetupMenuItem=&Giới thiệu trình cài đặt...
AboutSetupTitle=Giới thiệu trình cài đặt
AboutSetupMessage=%1 phiên bản %2%n%3%n%nTrang chủ %1:%n%4
AboutSetupNote=
TranslatorNote=Bản dịch Tiếng Việt cho FlClash Việt Hóa Lite

; *** 按钮
ButtonBack=< &Quay lại
ButtonNext=&Tiếp tục >
ButtonInstall=&Cài đặt
ButtonOK=OK
ButtonCancel=Hủy
ButtonYes=&Có
ButtonYesToAll=Có tất cả (&A)
ButtonNo=&Không
ButtonNoToAll=Không tất cả (&O)
ButtonFinish=&Hoàn tất
ButtonBrowse=&Chọn...
ButtonWizardBrowse=&Chọn...
ButtonNewFolder=&Thư mục mới

; *** “选择语言”对话框消息
SelectLanguageTitle=Chọn ngôn ngữ cài đặt
SelectLanguageLabel=Chọn ngôn ngữ sử dụng trong quá trình cài đặt.

; *** 公共向导文字
ClickNext=Nhấn Tiếp tục để tiếp diễn hoặc Hủy để thoát.
BeveledLabel=
BrowseDialogTitle=Chọn thư mục
BrowseDialogLabel=Chọn thư mục trong danh sách bên dưới và nhấn OK.
NewFolderName=Thư mục mới

; *** “欢迎”向导页
WelcomeLabel1=Chào mừng bạn đến với Trình cài đặt [name]
WelcomeLabel2=Quá trình này sẽ cài đặt [name/ver] vào máy tính của bạn.%n%nKhuyến nghị đóng các ứng dụng khác trước khi tiếp tục.

; *** “密码”向导页
WizardPassword=Mật khẩu
PasswordLabel1=Trình cài đặt này được bảo vệ bằng mật khẩu.
PasswordLabel3=Nhập mật khẩu và nhấn Tiếp tục. Mật khẩu có phân biệt chữ hoa/thường.
PasswordEditLabel=&Mật khẩu:
IncorrectPassword=Mật khẩu vừa nhập không đúng, vui lòng thử lại.

; *** “许可协议”向导页
WizardLicense=Thỏa thuận bản quyền
LicenseLabel=Vui lòng đọc kỹ thông tin quan trọng bên dưới trước khi tiếp tục.
LicenseLabel3=Vui lòng đọc thỏa thuận bản quyền sau. Bạn cần đồng ý để tiếp tục cài đặt.
LicenseAccepted=Tôi &đồng ý với thỏa thuận này
LicenseNotAccepted=Tôi &không đồng ý

; *** “信息”向导页
WizardInfoBefore=Thông tin
InfoBeforeLabel=Vui lòng đọc thông tin bên dưới trước khi tiếp tục.
InfoBeforeClickLabel=Khi đã sẵn sàng cài đặt, hãy nhấn Tiếp tục.
WizardInfoAfter=Thông tin
InfoAfterLabel=Vui lòng đọc thông tin bên dưới trước khi tiếp tục.
InfoAfterClickLabel=Khi đã sẵn sàng tiếp tục, hãy nhấn Tiếp tục.

; *** “用户信息”向导页
WizardUserInfo=Thông tin người dùng
UserInfoDesc=Vui lòng nhập thông tin của bạn.
UserInfoName=&Tên người dùng:
UserInfoOrg=&Tổ chức:
UserInfoSerial=Mã số (&S):
UserInfoNameRequired=Bạn phải nhập tên người dùng.

; *** “选择目标目录”向导页
WizardSelectDir=Chọn thư mục cài đặt
SelectDirDesc=Bạn muốn cài đặt [name] ở đâu?
SelectDirLabel3=Trình cài đặt sẽ cài [name] vào thư mục sau.
SelectDirBrowseLabel=Nhấn Tiếp tục để tiếp diễn. Nếu muốn đổi nơi lưu, nhấn Chọn.
DiskSpaceGBLabel=Cần ít nhất [gb] GB dung lượng trống trên ổ đĩa.
DiskSpaceMBLabel=Cần ít nhất [mb] MB dung lượng trống trên ổ đĩa.
CannotInstallToNetworkDrive=Không thể cài đặt lên ổ đĩa mạng.
CannotInstallToUNCPath=Không thể cài đặt vào đường dẫn mạng UNC.
InvalidPath=Vui lòng nhập đường dẫn đầy đủ kèm tên ổ đĩa, ví dụ:%n%nC:\APP%n%nhoặc đường dẫn UNC:%n%n\\server\share
InvalidDrive=Ổ đĩa hoặc đường dẫn vừa chọn không tồn tại hoặc không thể truy cập.
DiskSpaceWarningTitle=Không đủ dung lượng trống
DiskSpaceWarning=Cần tối thiểu %1 KB dung lượng trống để cài đặt, nhưng ổ đĩa chỉ còn %2 KB.%n%nBạn vẫn muốn tiếp tục chứ?
DirNameTooLong=Tên thư mục hoặc đường dẫn quá dài.
InvalidDirName=Tên thư mục không hợp lệ.
BadDirName32=Tên thư mục không được chứa các ký tự sau:%n%n%1
DirExistsTitle=Thư mục đã tồn tại
DirExists=Thư mục:%n%n%1%n%nđã tồn tại. Bạn vẫn muốn cài đặt vào thư mục này?
DirDoesntExistTitle=Thư mục chưa tồn tại
DirDoesntExist=Thư mục:%n%n%1%n%nchưa tồn tại. Bạn có muốn tạo mới thư mục này không?

; *** “选择组件”向导页
WizardSelectComponents=Chọn thành phần
SelectComponentsDesc=Bạn muốn cài đặt những thành phần nào?
SelectComponentsLabel2=Chọn thành phần muốn cài đặt hoặc bỏ chọn thành phần không cần thiết, sau đó nhấn Tiếp tục.
FullInstallation=Cài đặt đầy đủ
; if possible don't translate 'Compact' as 'Minimal' (I mean 'Minimal' in your language)
CompactInstallation=Cài đặt gọn nhẹ
CustomInstallation=Cài đặt tùy chọn
NoUninstallWarningTitle=Thành phần đã tồn tại
NoUninstallWarning=Các thành phần sau đã có trên máy tính:%n%n%1%n%nBỏ chọn sẽ không gỡ bỏ chúng.%n%nBạn vẫn muốn tiếp tục?
ComponentSize1=%1 KB
ComponentSize2=%1 MB
ComponentsDiskSpaceGBLabel=Các thành phần đã chọn cần ít nhất [gb] GB dung lượng trống.
ComponentsDiskSpaceMBLabel=Các thành phần đã chọn cần ít nhất [mb] MB dung lượng trống.

; *** “选择附加任务”向导页
WizardSelectTasks=Chọn tác vụ bổ sung
SelectTasksDesc=Bạn muốn thực hiện thêm tác vụ nào?
SelectTasksLabel2=Chọn tác vụ bổ sung khi cài đặt [name], sau đó nhấn Tiếp tục.

; *** “选择开始菜单文件夹”向导页
WizardSelectProgramGroup=Chọn thư mục Menu Start
SelectStartMenuFolderDesc=Đặt lối tắt chương trình ở đâu?
SelectStartMenuFolderLabel3=Trình cài đặt sẽ tạo lối tắt trong thư mục Menu Start sau.
SelectStartMenuFolderBrowseLabel=Nhấn Tiếp tục để tiếp diễn hoặc nhấn Chọn để đổi thư mục.
MustEnterGroupName=Bạn phải nhập tên thư mục.
GroupNameTooLong=Tên thư mục hoặc đường dẫn quá dài.
InvalidGroupName=Tên thư mục không hợp lệ.
BadGroupName=Tên thư mục không được chứa các ký tự sau:%n%n%1
NoProgramGroupCheck2=&Không tạo thư mục Menu Start

; *** “准备安装”向导页
WizardReady=Sẵn sàng cài đặt
ReadyLabel1=Trình cài đặt đã sẵn sàng cài [name] lên máy tính của bạn.
ReadyLabel2a=Nhấn Cài đặt để bắt đầu, hoặc Quay lại để xem lại tùy chọn.
ReadyLabel2b=Nhấn Cài đặt để bắt đầu.
ReadyMemoUserInfo=Thông tin người dùng:
ReadyMemoDir=Thư mục cài đặt:
ReadyMemoType=Kiểu cài đặt:
ReadyMemoComponents=Thành phần đã chọn:
ReadyMemoGroup=Thư mục Menu Start:
ReadyMemoTasks=Tác vụ bổ sung:

; *** TDownloadWizardPage wizard page and DownloadTemporaryFile
DownloadingLabel=Đang tải tệp bổ sung...
ButtonStopDownload=&Dừng tải
StopDownload=Bạn có chắc muốn dừng tải không?
ErrorDownloadAborted=Đã hủy tải xuống
ErrorDownloadFailed=Tải xuống thất bại: %1 %2
ErrorDownloadSizeFailed=Không lấy được kích thước tệp: %1 %2
ErrorFileHash1=Kiểm tra mã băm thất bại: %1
ErrorFileHash2=Mã băm không khớp: kỳ vọng %1, thực tế %2
ErrorProgress=Tiến trình không hợp lệ: %1 / %2
ErrorFileSize=Kích thước tệp không khớp: kỳ vọng %1, thực tế %2

; *** “正在准备安装”向导页
WizardPreparing=Đang chuẩn bị cài đặt
PreparingDesc=Đang chuẩn bị cài đặt [name] vào máy tính của bạn.
PreviousInstallNotCompleted=Lần cài đặt/gỡ trước chưa hoàn tất. Cần khởi động lại máy tính rồi chạy lại bộ cài [name].
CannotContinue=Không thể tiếp tục cài đặt. Nhấn Hủy để thoát.
ApplicationsFound=Các ứng dụng sau đang dùng tệp cần cập nhật. Khuyên dùng cho phép trình cài đặt tự đóng các ứng dụng này.
ApplicationsFound2=Các ứng dụng sau đang dùng tệp cần cập nhật. Sau khi xong, trình cài đặt sẽ cố gắng mở lại chúng.
CloseApplications=&Tự động đóng ứng dụng
DontCloseApplications=&Không đóng ứng dụng
ErrorCloseApplications=Không thể tự đóng tất cả ứng dụng đang chạy. Vui lòng đóng thủ công trước khi tiếp tục.
PrepareToInstallNeedsRestart=Cần khởi động lại máy tính để tiếp tục cài [name].%n%nBạn có muốn khởi động lại ngay?

; *** “正在安装”向导页
WizardInstalling=Đang cài đặt
InstallingLabel=Đang cài đặt [name] vào máy tính, vui lòng đợi trong giây lát.

; *** “安装完成”向导页
FinishedHeadingLabel=Đã cài xong [name]
FinishedLabelNoIcons=[name] đã được cài đặt thành công lên máy tính của bạn.
FinishedLabel=[name] đã được cài đặt lên máy tính. Bạn có thể mở app từ lối tắt vừa tạo.
ClickFinish=Nhấn Hoàn tất để đóng trình cài đặt.
FinishedRestartLabel=Cần khởi động lại máy tính để hoàn tất cài đặt [name]. Khởi động lại ngay?
FinishedRestartMessage=Cần khởi động lại máy tính để hoàn tất cài đặt [name].%n%nBạn có muốn khởi động lại ngay không?
ShowReadmeCheck=Xem tệp hướng dẫn (Readme)
YesRadio=&Có, khởi động lại máy ngay
NoRadio=&Không, tôi sẽ tự khởi động lại sau
; used for example as 'Run MyProg.exe'
RunEntryExec=Mở %1
; used for example as 'View Readme.txt'
RunEntryShellExec=Xem %1

; *** “安装程序需要下一张磁盘”提示
ChangeDiskTitle=Cần đĩa cài đặt tiếp theo
SelectDiskLabel2=Vui lòng đưa Đĩa %1 vào và nhấn OK.%n%nNếu tệp nằm ở thư mục khác, hãy nhập đường dẫn hoặc nhấn Chọn.
PathLabel=&Đường dẫn:
FileNotInDir2=Không tìm thấy tệp "%1" trong "%2". Vui lòng kiểm tra lại.
SelectDirectoryLabel=Chọn vị trí đĩa cài đặt tiếp theo.

; *** 安装状态消息
SetupAborted=Quá trình cài đặt chưa hoàn tất.%n%nVui lòng khắc phục lỗi và chạy lại bộ cài.
AbortRetryIgnoreSelectAction=Chọn thao tác
AbortRetryIgnoreRetry=&Thử lại
AbortRetryIgnoreIgnore=&Bỏ qua lỗi và tiếp tục
AbortRetryIgnoreCancel=Thoát trình cài đặt

; *** 安装状态消息
StatusClosingApplications=Đang đóng ứng dụng đang chạy...
StatusCreateDirs=Đang tạo thư mục...
StatusExtractFiles=Đang giải nén tệp...
StatusCreateIcons=Đang tạo lối tắt...
StatusCreateIniEntries=Đang ghi cấu hình INI...
StatusCreateRegistryEntries=Đang cập nhật Registry...
StatusRegisterFiles=Đang đăng ký tệp hệ thống...
StatusSavingUninstall=Đang lưu thông tin gỡ cài đặt...
StatusRunProgram=Đang hoàn tất cài đặt...
StatusRestartingApplications=Đang khởi động lại ứng dụng...
StatusRollback=Đang khôi phục thay đổi...

; *** 其它错误
ErrorInternal2=Lỗi nội bộ: %1
ErrorFunctionFailedNoCode=%1 thất bại
ErrorFunctionFailed=%1 thất bại; mã lỗi %2
ErrorFunctionFailedWithMessage=%1 thất bại; mã lỗi %2.%n%3
ErrorExecutingProgram=Không thể chạy tệp:%n%1

; *** 注册表错误
ErrorRegOpenKey=Lỗi mở khóa Registry:%n%1\%2
ErrorRegCreateKey=Lỗi tạo khóa Registry:%n%1\%2
ErrorRegWriteKey=Lỗi ghi khóa Registry:%n%1\%2

; *** INI 错误
ErrorIniEntry=Lỗi ghi mục INI trong tệp "%1".

; *** 文件复制错误
FileAbortRetryIgnoreSkipNotRecommended=&Bỏ qua tệp này (không khuyên dùng)
FileAbortRetryIgnoreIgnoreNotRecommended=&Bỏ qua lỗi và tiếp tục (không khuyên dùng)
SourceIsCorrupted=Tệp nguồn bị hỏng
SourceDoesntExist=Không tìm thấy tệp nguồn "%1"
ExistingFileReadOnly2=Không thể ghi đè tệp hiện có vì đang ở chế độ chỉ đọc.
ExistingFileReadOnlyRetry=&Gỡ thuộc tính chỉ đọc và thử lại
ExistingFileReadOnlyKeepExisting=&Giữ lại tệp hiện có
ErrorReadingExistingDest=Lỗi khi đọc tệp hiện có:
FileExistsSelectAction=Chọn thao tác
FileExists2=Tệp đã tồn tại.
FileExistsOverwriteExisting=&Ghi đè tệp hiện có
FileExistsKeepExisting=&Giữ nguyên tệp hiện có
FileExistsOverwriteOrKeepAll=&Áp dụng cho tất cả tệp trùng
ExistingFileNewerSelectAction=Chọn thao tác
ExistingFileNewer2=Tệp hiện có mới hơn tệp sắp cài đặt.
ExistingFileNewerOverwriteExisting=&Ghi đè tệp hiện có
ExistingFileNewerKeepExisting=&Giữ lại tệp hiện có (khuyên dùng)
ExistingFileNewerOverwriteOrKeepAll=&Áp dụng cho tất cả tệp trùng
ErrorChangingAttr=Lỗi đổi thuộc tính của tệp:
ErrorCreatingTemp=Lỗi tạo tệp trong thư mục đích:
ErrorReadingSource=Lỗi đọc tệp nguồn:
ErrorCopying=Lỗi sao chép tệp:
ErrorReplacingExistingFile=Lỗi thay thế tệp hiện có:
ErrorRestartReplace=Lỗi thay thế sau khi khởi động lại:
ErrorRenamingTemp=Lỗi đổi tên tệp trong thư mục đích:
ErrorRegisterServer=Không thể đăng ký DLL/OCX: %1
ErrorRegSvr32Failed=RegSvr32 thất bại; mã thoát %1
ErrorRegisterTypeLib=Không thể đăng ký thư viện kiểu: %1

; *** 卸载显示名字标记
; used for example as 'My Program (32-bit)'
UninstallDisplayNameMark=%1 (%2)
; used for example as 'My Program (32-bit, All users)'
UninstallDisplayNameMarks=%1 (%2, %3)
UninstallDisplayNameMark32Bit=32-bit
UninstallDisplayNameMark64Bit=64-bit
UninstallDisplayNameMarkAllUsers=Tất cả người dùng
UninstallDisplayNameMarkCurrentUser=Người dùng hiện tại

; *** 安装后错误
ErrorOpeningReadme=Lỗi mở tệp hướng dẫn.
ErrorRestartingComputer=Không thể tự khởi động lại máy tính, vui lòng khởi động lại thủ công.

; *** 卸载消息
UninstallNotFound=Không tìm thấy tệp "%1". Không thể gỡ cài đặt.
UninstallOpenError=Không mở được tệp "%1". Không thể gỡ cài đặt.
UninstallUnsupportedVer=Phiên bản trình gỡ không đọc được định dạng nhật ký "%1".
UninstallUnknownEntry=Gặp mục không xác định (%1) trong nhật ký gỡ cài đặt
ConfirmUninstall=Bạn có chắc muốn gỡ bỏ hoàn toàn %1 và tất cả thành phần liên quan?
UninstallOnlyOnWin64=Chương trình này chỉ gỡ được trên Windows 64-bit.
OnlyAdminCanUninstall=Chỉ tài khoản Quản trị viên mới có quyền gỡ ứng dụng này.
UninstallStatusLabel=Vui lòng chờ trong khi đang gỡ %1 khỏi máy tính của bạn.
UninstalledAll=Đã gỡ bỏ hoàn toàn %1 khỏi máy tính.
UninstalledMost=Đã gỡ %1.%n%nMột vài tệp còn sót có thể tự xóa thủ công.
UninstalledAndNeedsRestart=Cần khởi động lại máy tính để hoàn tất gỡ %1.%n%nKhởi động lại ngay?
UninstallDataCorrupted=Tệp "%1" bị hỏng, không thể gỡ cài đặt

; *** 卸载状态消息
ConfirmDeleteSharedFileTitle=Xóa tệp dùng chung?
ConfirmDeleteSharedFile2=Hệ thống phát hiện tệp dùng chung sau không còn ứng dụng nào dùng. Bạn có muốn xóa không?%n%nNếu không chắc chắn, hãy chọn Không để giữ lại an toàn.
SharedFileNameLabel=Tên tệp:
SharedFileLocationLabel=Vị trí:
WizardUninstalling=Trạng thái gỡ cài đặt
StatusUninstalling=Đang gỡ %1...

; *** Shutdown block reasons
ShutdownBlockReasonInstallingApp=Đang cài đặt %1.
ShutdownBlockReasonUninstallingApp=Đang gỡ %1.

; The custom messages below aren't used by Setup itself, but if you make
; use of them in your scripts, you'll want to translate them.

[CustomMessages]

NameAndVersion=%1 phiên bản %2
AdditionalIcons=Biểu tượng bổ sung:
CreateDesktopIcon=&Tạo biểu tượng ngoài Desktop
CreateQuickLaunchIcon=Tạo biểu tượng &Quick Launch
ProgramOnTheWeb=Trang web %1
UninstallProgram=Gỡ cài đặt %1
LaunchProgram=Mở %1
AssocFileExtension=&Liên kết phần mở rộng tệp %2 với %1
AssocingFileExtension=Đang liên kết tệp %2 với %1...
AutoStartProgramGroupDescription=Khởi động:
AutoStartProgram=Tự khởi động %1
AddonHostProgramNotFound=Không tìm thấy %1 trong thư mục bạn chọn.%n%nTiếp tục?
RemoveUserData=Đồng thời xóa toàn bộ cấu hình (profile) và cài đặt của bạn?
