# セキュリティグループの作成
resource "aws_security_group" "streamlit_sg" {
  name        = "streamlit-app-sg"
  description = "Security group for Streamlit application"
  vpc_id      = "vpc-0f717dce6b48fbe84"

  # SSH接続用
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Streamlit用ポート
  ingress {
    from_port   = 8501
    to_port     = 8501
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Streamlit access"
  }

  # アウトバウンドトラフィック
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name                      = "streamlit-app-sg"
    environment               = "a1b2-css-dev"
    app                       = "a1b2-css"
    application_id            = "CPMN-24F-0025"
  }
}

# EC2インスタンス用のIAMロール
resource "aws_iam_role" "ec2_role" {
  name = "streamlit-app-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    environment               = "a1b2-css-dev"
    app                       = "a1b2-css"
    application_id            = "CPMN-24F-0025"
  }
}

# EC2インスタンスプロファイル
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "streamlit-app-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# アプリケーションファイルをアップロードするためのS3バケット
resource "aws_s3_bucket" "app_bucket" {
  bucket = "streamlit-app-deployment-bucket"
  
  tags = {
    Name                      = "streamlit-app-bucket"
    environment               = "a1b2-css-dev"
    app                       = "a1b2-css"
    application_id            = "CPMN-24F-0025"
  }
}

# S3バケットへのアクセス権をEC2に付与
resource "aws_iam_policy" "s3_access_policy" {
  name        = "streamlit-app-s3-access"
  description = "Allow EC2 to access S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.app_bucket.arn,
          "${aws_s3_bucket.app_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_access_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

# アプリケーションファイルをS3にアップロード
resource "aws_s3_object" "app_py" {
  bucket = aws_s3_bucket.app_bucket.bucket
  key    = "app.py"
  source = "../app.py"
  etag   = filemd5("../app.py")
}

resource "aws_s3_object" "fw_transfer_py" {
  bucket = aws_s3_bucket.app_bucket.bucket
  key    = "FW_transfer.py"
  source = "../FW_transfer.py"
  etag   = filemd5("../FW_transfer.py")
}

resource "aws_s3_object" "requirements_txt" {
  bucket = aws_s3_bucket.app_bucket.bucket
  key    = "requirements.txt"
  source = "../requirements.txt"
  etag   = filemd5("../requirements.txt")
}

# EC2インスタンスの作成
resource "aws_instance" "streamlit_app" {
  ami                    = "ami-0d52744d6551d851e"  # Amazon Linux 2023 AMI (ap-northeast-1)
  instance_type          = "t3.micro"
  subnet_id              = "subnet-03f2e46fd89a0bd49"  # ap-northeast-1a
  vpc_security_group_ids = [aws_security_group.streamlit_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = "streamlit-app-key"  # 既存のキーペア名を指定するか、新しく作成する

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y python3 python3-pip git awscli

    # アプリケーションのデプロイ
    mkdir -p /opt/streamlit-app
    cd /opt/streamlit-app
    
    # S3からアプリケーションファイルをダウンロード
    aws s3 cp s3://${aws_s3_bucket.app_bucket.bucket}/app.py .
    aws s3 cp s3://${aws_s3_bucket.app_bucket.bucket}/FW_transfer.py .
    aws s3 cp s3://${aws_s3_bucket.app_bucket.bucket}/requirements.txt .
    
    # 出力ディレクトリのパスを修正（EC2インスタンス上で書き込み可能なパスに）
    sed -i 's|/Users/yuu/Desktop/|/tmp/|g' FW_transfer.py
    
    # 必要なパッケージをインストール
    pip3 install -r requirements.txt
    
    # Streamlitアプリを起動するためのサービスを作成
    cat > /etc/systemd/system/streamlit.service << 'SERVICEEOF'
[Unit]
Description=Streamlit Application
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/opt/streamlit-app
ExecStart=/usr/local/bin/streamlit run app.py --server.port=8501 --server.address=0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF

    # サービスを有効化して起動
    systemctl daemon-reload
    systemctl enable streamlit
    systemctl start streamlit
  EOF

  # S3オブジェクトが変更されたら、EC2インスタンスを再作成
  depends_on = [
    aws_s3_object.app_py,
    aws_s3_object.fw_transfer_py,
    aws_s3_object.requirements_txt
  ]

  tags = {
    Name                      = "streamlit-app-instance"
    environment               = "a1b2-css-dev"
    app                       = "a1b2-css"
    application_id            = "CPMN-24F-0025"
  }
}

# Elastic IPの割り当て
resource "aws_eip" "streamlit_eip" {
  instance = aws_instance.streamlit_app.id
  domain   = "vpc"

  tags = {
    Name                      = "streamlit-app-eip"
    environment               = "a1b2-css-dev"
    app                       = "a1b2-css"
    application_id            = "CPMN-24F-0025"
  }
}
